/**
 * POST /api/admin/feed/posts/bulk
 *
 * Bulk moderation actions untuk admin Feed dashboard. Admin select banyak
 * post sekaligus → 1 request bulk daripada N round-trips. Per-item result
 * di-return supaya UI bisa show partial success (mis. 8 approve, 2 skip
 * karena status sudah ACTIVE).
 *
 * Body:
 *   {
 *     action: "approve" | "reject" | "hide" | "unhide" | "restore"
 *           | "soft-delete" | "hard-delete",
 *     postIds: string[],
 *     note?: string  // wajib untuk action=reject
 *   }
 *
 * Response:
 *   {
 *     ok: true,
 *     results: [
 *       { postId: string, status: "applied" | "skipped" | "error", reason?: string }
 *     ],
 *     summary: { applied: N, skipped: N, error: N }
 *   }
 *
 * Setiap item di-process di transaction terpisah (bukan 1 big transaction)
 * supaya 1 row error tidak rollback semua. Audit log (FeedModerationLog)
 * tetap di-record per item.
 */
import { after, NextRequest, NextResponse } from "next/server";
import type { FeedPostStatus } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { deleteFeedAssets } from "@/lib/feed/cleanup";
import { decrementHashtagCounts } from "@/lib/feed/hashtags";
import { sendNewPostToFollowersNotification } from "@/lib/social/notifications";

// Cleanup asset + fan-out follower dijadwalkan via after() per item —
// tetap dihitung ke durasi invocation, beri ruang untuk batch besar.
export const maxDuration = 60;

type BulkAction =
  | "approve"
  | "reject"
  | "hide"
  | "unhide"
  | "restore"
  | "soft-delete"
  | "hard-delete";

const VALID_ACTIONS: BulkAction[] = [
  "approve",
  "reject",
  "hide",
  "unhide",
  "restore",
  "soft-delete",
  "hard-delete",
];

const TRANSITIONS: Record<
  Exclude<BulkAction, "restore" | "soft-delete" | "hard-delete">,
  { from: FeedPostStatus[]; to: FeedPostStatus; requireNote?: boolean }
> = {
  approve: { from: ["PENDING_REVIEW"], to: "ACTIVE" },
  reject: { from: ["PENDING_REVIEW"], to: "REJECTED", requireNote: true },
  hide: { from: ["ACTIVE"], to: "HIDDEN" },
  unhide: { from: ["HIDDEN"], to: "ACTIVE" },
};

// Maks bulk size per request — defensive cap supaya admin tidak accidentally
// hapus 1000+ post sekaligus. Kalau perlu lebih, harus batch.
const MAX_BULK_SIZE = 100;

type ItemResult = {
  postId: string;
  status: "applied" | "skipped" | "error";
  reason?: string;
};

export async function POST(request: NextRequest) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => ({}))) as {
    action?: string;
    postIds?: unknown;
    note?: string;
  };

  const action = String(body.action ?? "");
  if (!(VALID_ACTIONS as string[]).includes(action)) {
    return NextResponse.json(
      { error: `Action invalid. Pilih: ${VALID_ACTIONS.join(", ")}.` },
      { status: 400 },
    );
  }

  const postIds = Array.isArray(body.postIds)
    ? [
        ...new Set(
          body.postIds
            .map((v) => String(v ?? "").trim())
            .filter(Boolean),
        ),
      ]
    : [];

  if (postIds.length === 0) {
    return NextResponse.json(
      { error: "Pilih minimal 1 post." },
      { status: 400 },
    );
  }
  if (postIds.length > MAX_BULK_SIZE) {
    return NextResponse.json(
      {
        error: `Maksimal ${MAX_BULK_SIZE} post per request. Pilih lebih sedikit atau split jadi batch.`,
      },
      { status: 400 },
    );
  }

  const noteStr =
    typeof body.note === "string" ? body.note.trim().slice(0, 500) : "";

  // Validasi note required untuk reject — return error sebelum loop supaya
  // admin tahu duluan (instead of 100 individual "no note" errors).
  if (action === "reject" && !noteStr) {
    return NextResponse.json(
      { error: "Catatan alasan wajib diisi untuk bulk reject." },
      { status: 400 },
    );
  }

  // Fetch semua post sekaligus — lebih efisien dari N findUnique calls.
  const posts = await prisma.feedPost.findMany({
    where: { id: { in: postIds } },
    select: {
      id: true,
      status: true,
      deletedAt: true,
      publishedAt: true,
      videoUrl: true,
      thumbnailUrl: true,
      videoGuid: true,
      // Dipakai untuk skip approve atas video yang belum playable —
      // listFeedPosts filter encodingStatus="ready", jadi approve sebelum
      // encoding kelar bikin post "approved tapi invisible".
      encodingStatus: true,
    },
  });
  const postMap = new Map(posts.map((p) => [p.id, p]));

  const results: ItemResult[] = [];
  // Process per item — bukan 1 big transaction supaya 1 error tidak
  // rollback semua. Kalau perlu performa lebih, bisa di-batch ke Prisma
  // updateMany nanti, tapi audit log per item lebih akurat dengan
  // per-item transaction.
  for (const postId of postIds) {
    const post = postMap.get(postId);
    if (!post) {
      results.push({ postId, status: "error", reason: "Post tidak ditemukan" });
      continue;
    }

    try {
      if (action === "hard-delete") {
        // Spec C: kurangi postCount hashtag SEBELUM delete (satu transaksi
        // dengan delete) — cascade menghapus baris junction FeedPostHashtag
        // yang jadi sumber decrementHashtagCounts. Sama pattern dengan
        // app/api/admin/feed/posts/[id]/route.ts (single hard-delete).
        await prisma.$transaction(async (tx) => {
          await decrementHashtagCounts(tx, postId);
          await tx.feedPost.delete({ where: { id: postId } });
        });
        // Via after() (bukan void) — void promise bisa dibekukan Vercel
        // sebelum jalan → orphan asset; after() dijamin eksekusi tanpa
        // menahan respons bulk.
        after(() =>
          deleteFeedAssets({
            videoUrl: post.videoUrl,
            thumbnailUrl: post.thumbnailUrl,
            videoGuid: post.videoGuid,
            context: `bulk hard-delete ${postId}`,
          }),
        );
        results.push({ postId, status: "applied" });
        continue;
      }

      if (action === "soft-delete") {
        if (post.deletedAt) {
          results.push({
            postId,
            status: "skipped",
            reason: "Sudah di sampah",
          });
          continue;
        }
        const now = new Date();
        await prisma.$transaction([
          prisma.feedPost.update({
            where: { id: postId },
            data: {
              deletedAt: now,
              moderatedById: session.sub,
              moderatedAt: now,
            },
          }),
          prisma.feedModerationLog.create({
            data: {
              postId,
              actorId: session.sub,
              action: "delete",
              fromStatus: post.status,
              toStatus: post.status,
              note: noteStr || null,
            },
          }),
        ]);
        // Via after() — alasan sama dengan hard-delete di atas.
        after(() =>
          deleteFeedAssets({
            videoUrl: post.videoUrl,
            thumbnailUrl: post.thumbnailUrl,
            videoGuid: post.videoGuid,
            context: `bulk soft-delete ${postId}`,
          }),
        );
        results.push({ postId, status: "applied" });
        continue;
      }

      if (action === "restore") {
        // Soft-deleted → lift deletedAt
        if (post.deletedAt) {
          await prisma.$transaction([
            prisma.feedPost.update({
              where: { id: postId },
              data: {
                deletedAt: null,
                moderatedById: session.sub,
                moderatedAt: new Date(),
              },
            }),
            prisma.feedModerationLog.create({
              data: {
                postId,
                actorId: session.sub,
                action: "restore",
                fromStatus: post.status,
                toStatus: post.status,
                note: "bulk restore from soft-delete",
              },
            }),
          ]);
          results.push({ postId, status: "applied" });
          continue;
        }
        // Terminal status → flip back
        let toStatus: FeedPostStatus;
        if (post.status === "REJECTED") toStatus = "PENDING_REVIEW";
        else if (post.status === "HIDDEN") toStatus = "ACTIVE";
        else {
          results.push({
            postId,
            status: "skipped",
            reason: `Tidak perlu restore (status: ${post.status})`,
          });
          continue;
        }
        await prisma.$transaction([
          prisma.feedPost.update({
            where: { id: postId },
            data: {
              status: toStatus,
              moderatedById: session.sub,
              moderatedAt: new Date(),
              moderationNote: null,
            },
          }),
          prisma.feedModerationLog.create({
            data: {
              postId,
              actorId: session.sub,
              action: "restore",
              fromStatus: post.status,
              toStatus,
              note: noteStr || null,
            },
          }),
        ]);
        results.push({ postId, status: "applied" });
        continue;
      }

      // Standard transitions (approve/reject/hide/unhide)
      const transition =
        TRANSITIONS[action as Exclude<BulkAction, "restore" | "soft-delete" | "hard-delete">];
      if (!transition.from.includes(post.status)) {
        results.push({
          postId,
          status: "skipped",
          reason: `Status ${post.status} tidak bisa ${action}`,
        });
        continue;
      }

      // Skip approve untuk video yang belum playable. Bulk path TIDAK
      // auto-reconcile (single endpoint sudah cover itu) — admin yang
      // bulk-approve diasumsikan sudah lihat encoding badge di UI.
      if (action === "approve" && post.encodingStatus !== "ready") {
        const reason =
          post.encodingStatus === "failed"
            ? "Video encoding gagal"
            : post.encodingStatus === "uploading"
              ? "Upload belum selesai"
              : "Video masih di-encode";
        results.push({ postId, status: "skipped", reason });
        continue;
      }

      const now = new Date();
      await prisma.$transaction([
        prisma.feedPost.update({
          where: { id: postId },
          data: {
            status: transition.to,
            moderatedById: session.sub,
            moderatedAt: now,
            moderationNote: noteStr || null,
            publishedAt:
              action === "approve" && !post.publishedAt
                ? now
                : post.publishedAt,
          },
        }),
        prisma.feedModerationLog.create({
          data: {
            postId,
            actorId: session.sub,
            action,
            fromStatus: post.status,
            toStatus: transition.to,
            note: noteStr || null,
          },
        }),
      ]);

      // Reject = terminal → free Bunny asset (sama spt single endpoint).
      if (action === "reject") {
        // Via after() — alasan sama dengan hard-delete di atas.
        after(() =>
          deleteFeedAssets({
            videoUrl: post.videoUrl,
            thumbnailUrl: post.thumbnailUrl,
            videoGuid: post.videoGuid,
            context: `bulk reject ${postId}`,
          }),
        );
      }

      // Notif follower saat APPROVE (PENDING_REVIEW → ACTIVE), bukan unhide.
      // Helper dedup internal + skip author admin. Via after() (bukan void)
      // — void promise bisa dibekukan Vercel → notif follower hilang.
      if (action === "approve" && post.status === "PENDING_REVIEW") {
        after(() => sendNewPostToFollowersNotification(postId));
      }

      results.push({ postId, status: "applied" });
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "Unknown DB error";
      results.push({ postId, status: "error", reason: message });
    }
  }

  const summary = results.reduce(
    (acc, r) => {
      acc[r.status] = (acc[r.status] ?? 0) + 1;
      return acc;
    },
    {} as Record<string, number>,
  );

  return NextResponse.json({
    ok: true,
    results,
    summary: {
      applied: summary.applied ?? 0,
      skipped: summary.skipped ?? 0,
      error: summary.error ?? 0,
    },
  });
}
