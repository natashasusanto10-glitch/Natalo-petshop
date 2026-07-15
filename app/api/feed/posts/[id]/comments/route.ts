/**
 * GET /api/feed/posts/[id]/comments?cursor=<commentId>  — list (lazy)
 * POST /api/feed/posts/[id]/comments  — add comment (auth required)
 *
 * Spec 10.7: comments lazy-loaded. User tap icon comment → load 20+pagination.
 * Posting: transaction supaya commentCount counter di-sync atomic.
 * Admin reply (parentCommentId set, isAdminOfficial=true) belum di-implement
 * dalam endpoint ini — admin akan reply via /api/admin/feed/* di F5.
 */
import { after, NextRequest, NextResponse } from "next/server";
import { Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { listFeedComments } from "@/lib/feed/queries";
import { brandDisplayName, brandPhotoUrl } from "@/lib/social/brand-user";
import {
  sendCommentNotification,
  sendMentionNotifications,
  sendReplyNotification,
} from "@/lib/feed/activity-notifications";
import {
  extractMentionHandles,
  resolveMentionedUsers,
} from "@/lib/feed/mentions";
import {
  countedFeedCommentWhere,
  findChangedFeedCommentRootIds,
  findRemovedFeedCommentIds,
  readDatabaseSnapshotClock,
  resolveFeedCommentSyncWindow,
} from "@/lib/feed/comment-sync";
import {
  checkFeedCommentRateLimit,
  COMMENT_RATE_LIMIT_PER_WINDOW,
  COMMENT_RATE_LIMIT_WINDOW_MS,
} from "@/lib/feed/comment-rate-limit";
import { lockFeedInteractionActor } from "@/lib/feed/like-state";
import type { FeedCommentsSyncResponse } from "@/lib/feed/types";

const MAX_COMMENT_LENGTH = 1000;

/**
 * Anti-spam rate limit untuk komentar.
 *
 * Window 5 menit, max 10 komentar per user. Window-based count (bukan
 * proper leaky bucket per-second), tapi cukup efektif untuk Natalo scale:
 *   - User normal: 2-3 komentar / 5 menit (rapid back-and-forth chat)
 *   - User aktif diskusi: 5-7 / 5 menit (interactive thread)
 *   - Spammer / troll: 50+ dalam 30 detik = block keras
 *
 * Count over BOTH top-level + replies — supaya troll yang reply spam ke
 * 1 komentar berkali-kali tetap kena limit. Authors di-track via
 * authorId, jadi tidak per-post (1 user gak bisa workaround dengan ganti
 * post).
 *
 * Admin exempt — mereka perlu reply moderasi cepat.
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const { searchParams } = new URL(request.url);
  const cursor = searchParams.get("cursor") || null;
  const rawSyncCursor = searchParams.get("syncCursor");
  const rawSyncTime = searchParams.get("syncTime");

  const session = await getSession().catch(() => null);
  const result = await prisma.$transaction(
    async (tx) => {
      const syncTime = await readDatabaseSnapshotClock(tx);
      const post = await tx.feedPost.findUnique({
        where: { id: postId },
        select: {
          status: true,
          deletedAt: true,
          commentSyncCursor: true,
        },
      });
      if (!post || post.status !== "ACTIVE" || post.deletedAt) return null;

      const syncWindow = resolveFeedCommentSyncWindow({
        syncCursor: rawSyncCursor,
        syncTime: rawSyncTime,
        now: syncTime,
        currentCursor: post.commentSyncCursor,
      });
      const changes = await findChangedFeedCommentRootIds({
        db: tx,
        postId,
        since: syncWindow.since,
        until: post.commentSyncCursor,
      });
      const page = await listFeedComments({
        postId,
        cursor,
        viewerUserId: session?.sub ?? null,
        additionalRootIds: changes.rootCommentIds,
        db: tx,
      });
      const commentCount = await tx.feedComment.count({
        where: countedFeedCommentWhere(postId),
      });
      const removals = await findRemovedFeedCommentIds({
        db: tx,
        postId,
        since: syncWindow.since,
        until: post.commentSyncCursor,
      });
      const serializedSyncCursor = post.commentSyncCursor.toISOString();
      const changedRootIds = new Set(changes.rootCommentIds);

      return {
        ...page,
        commentCount,
        syncCursor: serializedSyncCursor,
        // Backward-compatible alias for clients that still send syncTime.
        // It must be the serialized commit cursor, not a wall-clock value.
        syncTime: serializedSyncCursor,
        changedItems: page.items.filter((item) => changedRootIds.has(item.id)),
        removedCommentIds: removals.removedCommentIds,
        syncResetRequired:
          syncWindow.resetRequired ||
          changes.resetRequired ||
          removals.resetRequired,
      } satisfies FeedCommentsSyncResponse;
    },
    {
      isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead,
    }
  );
  if (!result) {
    return NextResponse.json(
      { error: "Post tidak ditemukan" },
      { status: 404 }
    );
  }

  return NextResponse.json(result);
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession();
  if (!session) {
    return NextResponse.json(
      { error: "Login dulu untuk komentar." },
      { status: 401 }
    );
  }

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const post = await prisma.feedPost.findUnique({
    where: { id: postId },
    select: { id: true, status: true, deletedAt: true },
  });
  if (!post || post.status !== "ACTIVE" || post.deletedAt) {
    return NextResponse.json(
      { error: "Post tidak ditemukan" },
      { status: 404 }
    );
  }

  const body = await request.json().catch(() => ({}));
  const content = String((body as { content?: unknown }).content ?? "").trim();
  if (!content) {
    return NextResponse.json(
      { error: "Komentar tidak boleh kosong." },
      { status: 400 }
    );
  }
  if (content.length > MAX_COMMENT_LENGTH) {
    return NextResponse.json(
      { error: `Komentar maksimal ${MAX_COMMENT_LENGTH} karakter.` },
      { status: 400 }
    );
  }

  // Anti-spam: max 10 unique @mention per komentar. Cegah DDoS notif
  // via mention flooding (e.g. 100 user di-tag sekaligus). Block sebelum
  // create comment supaya gak waste DB row + notif worker time.
  const mentionHandlesEarly = extractMentionHandles(content);
  if (mentionHandlesEarly.size > 10) {
    return NextResponse.json(
      {
        error: `Maksimal 10 mention per komentar (kamu pakai ${mentionHandlesEarly.size}).`,
      },
      { status: 400 }
    );
  }

  const rawParent = (body as { parentCommentId?: unknown }).parentCommentId;
  let parentCommentId =
    typeof rawParent === "string" && rawParent ? rawParent : null;

  // Verify parent comment exists + masih di post yang sama (kalau ada).
  if (parentCommentId) {
    const parent = await prisma.feedComment.findUnique({
      where: { id: parentCommentId },
      select: {
        id: true,
        postId: true,
        parentCommentId: true,
        isHidden: true,
        deletedAt: true,
        parent: {
          select: { id: true, isHidden: true, deletedAt: true },
        },
      },
    });
    if (
      !parent ||
      parent.postId !== postId ||
      parent.isHidden ||
      parent.deletedAt
    ) {
      return NextResponse.json(
        { error: "Komentar parent tidak valid." },
        { status: 400 }
      );
    }
    if (parent.parentCommentId) {
      if (!parent.parent || parent.parent.isHidden || parent.parent.deletedAt) {
        return NextResponse.json(
          { error: "Thread komentar sudah tidak tersedia." },
          { status: 400 }
        );
      }
      // Thread dibatasi satu level: reply ke reply menjadi anak root.
      parentCommentId = parent.parent.id;
    } else {
      parentCommentId = parent.id;
    }
  }

  const isAdmin = session.role === "ADMIN";

  const result = await prisma.$transaction(async (tx) => {
    const actorAvailable = await lockFeedInteractionActor(tx, session.sub);
    if (!actorAvailable) {
      return { kind: "account-unavailable" } as const;
    }

    if (!isAdmin) {
      const rateLimit = await checkFeedCommentRateLimit({
        db: tx,
        userId: session.sub,
        limit: COMMENT_RATE_LIMIT_PER_WINDOW,
        windowMs: COMMENT_RATE_LIMIT_WINDOW_MS,
      });
      if (rateLimit.limited) {
        return {
          kind: "rate-limited",
          retryAfterMs: rateLimit.retryAfterMs,
        } as const;
      }
    }

    // Serialize create/delete pada post yang sama. Parent divalidasi ulang
    // setelah lock supaya reply tidak masuk saat thread sedang dihapus.
    const lockedPosts = await tx.$queryRaw<
      Array<{ id: string; status: string; deletedAt: Date | null }>
    >`
      SELECT "id", "status", "deletedAt" FROM "FeedPost"
      WHERE "id" = ${postId}
      FOR UPDATE
    `;
    const livePost = lockedPosts[0];
    if (!livePost || livePost.status !== "ACTIVE" || livePost.deletedAt) {
      return { kind: "post-not-found" } as const;
    }
    if (parentCommentId) {
      const liveParent = await tx.feedComment.findUnique({
        where: { id: parentCommentId },
        select: {
          postId: true,
          parentCommentId: true,
          isHidden: true,
          deletedAt: true,
        },
      });
      if (
        !liveParent ||
        liveParent.postId !== postId ||
        liveParent.parentCommentId !== null ||
        liveParent.isHidden ||
        liveParent.deletedAt
      ) {
        return { kind: "thread-unavailable" } as const;
      }
    }
    const comment = await tx.feedComment.create({
      data: {
        postId,
        authorId: session.sub,
        parentCommentId,
        content,
        isAdminOfficial: isAdmin,
      },
      include: {
        // BUG FIX: tambah profilePhotoUrl ke author select. Sebelumnya
        // POST response author hanya {id, name, role} → Flutter parse
        // author dengan profilePhotoUrl=null → avatar fallback ke
        // initial saat user post komentar baru. GET listing sudah benar
        // (lihat lib/feed/queries.ts mapFeedComment), bug cuma di
        // create-then-return path.
        author: {
          select: {
            id: true,
            name: true,
            username: true,
            role: true,
            profilePhotoUrl: true,
          },
        },
      },
    });
    // Reconcile from the canonical visible rows while the post lock is held.
    // This repairs historical drift instead of carrying it forward with an
    // increment-only counter.
    const commentCount = await tx.feedComment.count({
      where: countedFeedCommentWhere(postId),
    });
    await tx.feedPost.update({
      where: { id: postId },
      data: { commentCount },
    });
    return {
      kind: "created",
      comment,
      postCommentCount: commentCount,
    } as const;
  });
  if (result.kind === "account-unavailable") {
    return NextResponse.json(
      { error: "Sesi tidak berlaku" },
      { status: 401 }
    );
  }
  if (result.kind === "rate-limited") {
    return NextResponse.json(
      {
        error: "Kamu komentar terlalu cepat. Coba lagi dalam beberapa menit.",
        rateLimited: true,
        retryAfterMs: result.retryAfterMs,
      },
      { status: 429 }
    );
  }
  if (result.kind === "post-not-found") {
    return NextResponse.json(
      { error: "Post tidak ditemukan" },
      { status: 404 }
    );
  }
  if (result.kind === "thread-unavailable") {
    return NextResponse.json(
      { error: "Thread komentar sudah tidak tersedia." },
      { status: 400 }
    );
  }
  const created = result.comment;

  // Activity notification via `after()` (bukan `void`) — void promise bisa
  // dibekukan Vercel sebelum jalan → notif hilang; after() dijamin eksekusi
  // setelah response tanpa menahan komentar muncul. Reply path goes to the
  // parent comment's author; top-level comment goes to the post author.
  // Helpers skip self-notify + admin-authored posts internally.
  if (parentCommentId) {
    after(() =>
      sendReplyNotification({
        parentCommentId,
        replyCommentId: created.id,
        postId,
        actorUserId: session.sub,
        content,
      })
    );
  } else {
    after(() =>
      sendCommentNotification({
        postId,
        commentId: created.id,
        actorUserId: session.sub,
        content,
      })
    );
  }

  // @mention notification — separate dari reply/comment notif supaya user
  // yang di-mention dapat alert spesifik "@asiong menyebut kamu", bukan
  // notif post-author generic. Fire ke SEMUA user yang di-mention di
  // text. Dedup via tag di sendMentionNotifications. Skip kalau actor
  // sendiri ada di list (self-mention). Via after() — bukan void IIFE
  // yang bisa dibekukan Vercel sebelum jalan.
  after(async () => {
    try {
      const handles = extractMentionHandles(content);
      if (handles.size === 0) return;
      const mentioned = await resolveMentionedUsers(handles, session.sub);
      if (mentioned.length === 0) return;
      await sendMentionNotifications({
        actorUserId: session.sub,
        recipientUserIds: mentioned.map((u) => u.id),
        source: "comment",
        postId,
        commentId: created.id,
        excerpt: content,
      });
    } catch (err) {
      console.warn("[comments] mention notif failed:", err);
    }
  });

  return NextResponse.json({
    ok: true,
    commentCount: result.postCommentCount,
    comment: {
      id: created.id,
      postId: created.postId,
      parentCommentId: created.parentCommentId,
      content: created.content,
      isAdminOfficial: created.isAdminOfficial,
      isHidden: false,
      likeCount: 0,
      createdAt: created.createdAt.toISOString(),
      author: {
        id: created.author.id,
        // Akun official (admin) → brand name + foto null (klien render
        // logo). Nama asli/foto pemilik tidak boleh bocor di komentar.
        name: brandDisplayName(created.author.role, created.author.name),
        username: created.author.username ?? null,
        role: (created.author.role === "ADMIN" ? "ADMIN" : "CUSTOMER") as
          | "ADMIN"
          | "CUSTOMER",
        // Include profilePhotoUrl di response — match shape dengan GET
        // listing supaya Flutter dapat tampil avatar foto user yang
        // benar saat comment baru pertama kali muncul di drawer.
        profilePhotoUrl: brandPhotoUrl(
          created.author.role,
          created.author.profilePhotoUrl
        ),
      },
      viewerLiked: false,
    },
  });
}
