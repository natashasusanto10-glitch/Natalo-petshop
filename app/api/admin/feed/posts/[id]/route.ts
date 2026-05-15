/**
 * PATCH /api/admin/feed/posts/[id]
 *   Body: { action: "approve" | "reject" | "hide" | "unhide", note?: string }
 *
 *   Transition rules:
 *   - approve: PENDING_REVIEW → ACTIVE (set publishedAt = now)
 *   - reject:  PENDING_REVIEW → REJECTED (require note)
 *   - hide:    ACTIVE         → HIDDEN  (note opsional)
 *   - unhide:  HIDDEN         → ACTIVE
 *   (Status invalid → 400)
 *
 * DELETE /api/admin/feed/posts/[id]  — hard delete (cascade FK).
 *
 * Audit trail: moderatedById, moderatedAt, moderationNote (di REJECT/HIDE).
 */
import { NextRequest, NextResponse } from "next/server";
import type { FeedPostStatus } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { sendFeedModerationNotification } from "@/lib/feed/notifications";
import { deleteFeedAssets } from "@/lib/feed/cleanup";

type ModerationAction = "approve" | "reject" | "hide" | "unhide" | "restore";
const VALID_ACTIONS: ModerationAction[] = [
  "approve",
  "reject",
  "hide",
  "unhide",
  "restore",
];

// Transition map: { action: { fromStatus, toStatus } }. Restore intentionally
// allows transition out of REJECTED back to PENDING_REVIEW (re-queue) or out
// of HIDDEN back to ACTIVE (untrash). Admin can also restore a hard-deleted
// post — that path is gated on deletedAt instead and handled separately.
const TRANSITIONS: Record<
  Exclude<ModerationAction, "restore">,
  { from: FeedPostStatus[]; to: FeedPostStatus; requireNote?: boolean }
> = {
  approve: { from: ["PENDING_REVIEW"], to: "ACTIVE" },
  reject: { from: ["PENDING_REVIEW"], to: "REJECTED", requireNote: true },
  hide: { from: ["ACTIVE"], to: "HIDDEN" },
  unhide: { from: ["HIDDEN"], to: "ACTIVE" },
};

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const body = await request.json().catch(() => ({}));
  const action = String((body as { action?: unknown }).action ?? "");
  const note = (body as { note?: unknown }).note;
  const noteStr = typeof note === "string" ? note.trim().slice(0, 500) : "";

  if (!(VALID_ACTIONS as string[]).includes(action)) {
    return NextResponse.json(
      { error: "Action harus salah satu: approve/reject/hide/unhide/restore." },
      { status: 400 },
    );
  }

  // Restore goes through a different code path (it inverts whichever
  // soft-delete or terminal-status state the post is in).
  if (action === "restore") {
    return await handleRestore(postId, session.sub);
  }

  const transition = TRANSITIONS[action as Exclude<ModerationAction, "restore">];
  if (transition.requireNote && !noteStr) {
    return NextResponse.json(
      { error: "Catatan alasan wajib diisi untuk reject." },
      { status: 400 },
    );
  }

  const post = await prisma.feedPost.findUnique({
    where: { id: postId },
    select: {
      id: true,
      status: true,
      publishedAt: true,
      videoUrl: true,
      thumbnailUrl: true,
    },
  });
  if (!post) {
    return NextResponse.json({ error: "Post tidak ditemukan." }, { status: 404 });
  }
  if (!transition.from.includes(post.status)) {
    return NextResponse.json(
      {
        error: `Tidak bisa ${action} dari status ${post.status}. Diperlukan: ${transition.from.join(" / ")}.`,
      },
      { status: 409 },
    );
  }

  const now = new Date();
  const [updated] = await prisma.$transaction([
    prisma.feedPost.update({
      where: { id: postId },
      data: {
        status: transition.to,
        moderatedById: session.sub,
        moderatedAt: now,
        moderationNote: noteStr || null,
        // approve set publishedAt kalau belum ada; unhide tidak ubah
        // (publishedAt tetap timestamp ACTIVE pertama).
        publishedAt:
          action === "approve" && !post.publishedAt ? now : post.publishedAt,
      },
      select: {
        id: true,
        status: true,
        moderatedAt: true,
        moderationNote: true,
        publishedAt: true,
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

  // Notify the post author via push + notification center. Fire-and-forget
  // by design — Notification helper swallows its own errors so a failure
  // here can never roll back the moderation transition the admin just made.
  // Restore goes through handleRestore() above and isn't handled here.
  void sendFeedModerationNotification({
    postId,
    action: action as Exclude<ModerationAction, "restore">,
    note: noteStr || null,
  });

  // Storage cleanup. Reject is terminal — free the video + thumbnail from
  // UploadThing since the post will never come back. Hide is reversible
  // via unhide so we KEEP the assets; otherwise an admin hide/unhide round
  // trip leaves an ACTIVE post with no playable video. The weekly storage
  // GC cron (/api/cron/feed-storage-gc) catches truly orphan hidden posts
  // after they sit untouched for a while.
  if (action === "reject") {
    void deleteFeedAssets({
      videoUrl: post.videoUrl,
      thumbnailUrl: post.thumbnailUrl,
      context: `${action} ${postId}`,
    });
  }

  return NextResponse.json({
    ok: true,
    post: {
      id: updated.id,
      status: updated.status,
      moderatedAt: updated.moderatedAt?.toISOString() ?? null,
      moderationNote: updated.moderationNote,
      publishedAt: updated.publishedAt?.toISOString() ?? null,
    },
  });
}

/**
 * DELETE soft-deletes the post (sets deletedAt) and frees the UploadThing
 * assets. The row stays in the DB so admins still have the audit log and
 * the option to restore the metadata (re-upload would be required for
 * media). Pass `?hard=1` to bypass soft-delete and remove the row entirely
 * (cascade FK still cleans comments/likes/reports). Hard-delete is
 * destructive and intentionally not the default.
 */
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const hard = request.nextUrl.searchParams.get("hard") === "1";

  const existing = await prisma.feedPost.findUnique({
    where: { id: postId },
    select: { id: true, status: true, videoUrl: true, thumbnailUrl: true, deletedAt: true },
  });
  if (!existing) {
    return NextResponse.json({ error: "Post tidak ditemukan." }, { status: 404 });
  }

  if (hard) {
    // Hard delete: remove row (FK cascade clears comments/likes/reports/
    // audit log) and free storage. Audit trail is lost — only use when
    // truly purging.
    await prisma.feedPost.delete({ where: { id: postId } });
    void deleteFeedAssets({
      videoUrl: existing.videoUrl,
      thumbnailUrl: existing.thumbnailUrl,
      context: `hard-delete ${postId}`,
    });
    return NextResponse.json({ ok: true, mode: "hard" });
  }

  // Soft delete: tombstone via deletedAt + log + storage cleanup. Row
  // stays for audit / restore.
  if (existing.deletedAt) {
    return NextResponse.json(
      { ok: true, mode: "soft", alreadyDeleted: true },
      { status: 200 },
    );
  }

  await prisma.$transaction([
    prisma.feedPost.update({
      where: { id: postId },
      data: {
        deletedAt: new Date(),
        moderatedById: session.sub,
        moderatedAt: new Date(),
      },
    }),
    prisma.feedModerationLog.create({
      data: {
        postId,
        actorId: session.sub,
        action: "delete",
        fromStatus: existing.status,
        toStatus: existing.status, // soft delete doesn't change status enum
        note: null,
      },
    }),
  ]);

  void deleteFeedAssets({
    videoUrl: existing.videoUrl,
    thumbnailUrl: existing.thumbnailUrl,
    context: `soft-delete ${postId}`,
  });

  return NextResponse.json({ ok: true, mode: "soft" });
}

/**
 * Restore an admin moderation action. Handles three cases:
 *   1. Soft-deleted (deletedAt set) → clear deletedAt, keep current status.
 *   2. REJECTED → back to PENDING_REVIEW (re-queue for human review).
 *   3. HIDDEN   → back to ACTIVE (untrash, become visible again).
 * Media assets were freed when the post was rejected/hidden/deleted —
 * restore here only brings back the metadata. UI should warn the admin
 * that videoUrl may be broken; re-upload is the only way to restore media.
 */
async function handleRestore(postId: string, actorId: string) {
  const post = await prisma.feedPost.findUnique({
    where: { id: postId },
    select: { id: true, status: true, deletedAt: true },
  });
  if (!post) {
    return NextResponse.json({ error: "Post tidak ditemukan." }, { status: 404 });
  }

  // If soft-deleted, lift the tombstone first; status itself stays.
  if (post.deletedAt) {
    await prisma.$transaction([
      prisma.feedPost.update({
        where: { id: postId },
        data: { deletedAt: null, moderatedById: actorId, moderatedAt: new Date() },
      }),
      prisma.feedModerationLog.create({
        data: {
          postId,
          actorId,
          action: "restore",
          fromStatus: post.status,
          toStatus: post.status,
          note: "restore from soft-delete",
        },
      }),
    ]);
    return NextResponse.json({ ok: true, mode: "restored-from-trash" });
  }

  // Else flip terminal status back to a visible state.
  let toStatus: FeedPostStatus;
  if (post.status === "REJECTED") toStatus = "PENDING_REVIEW";
  else if (post.status === "HIDDEN") toStatus = "ACTIVE";
  else {
    return NextResponse.json(
      {
        error: `Tidak ada yang perlu di-restore dari status ${post.status}.`,
      },
      { status: 409 },
    );
  }

  await prisma.$transaction([
    prisma.feedPost.update({
      where: { id: postId },
      data: {
        status: toStatus,
        moderatedById: actorId,
        moderatedAt: new Date(),
        moderationNote: null,
      },
    }),
    prisma.feedModerationLog.create({
      data: {
        postId,
        actorId,
        action: "restore",
        fromStatus: post.status,
        toStatus,
        note: null,
      },
    }),
  ]);

  return NextResponse.json({ ok: true, mode: "restored-status", toStatus });
}
