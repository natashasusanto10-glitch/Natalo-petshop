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

type ModerationAction = "approve" | "reject" | "hide" | "unhide";
const VALID_ACTIONS: ModerationAction[] = ["approve", "reject", "hide", "unhide"];

// Transition map: { action: { fromStatus, toStatus } }
const TRANSITIONS: Record<
  ModerationAction,
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
      { error: "Action harus salah satu: approve/reject/hide/unhide." },
      { status: 400 },
    );
  }
  const transition = TRANSITIONS[action as ModerationAction];
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
  const updated = await prisma.feedPost.update({
    where: { id: postId },
    data: {
      status: transition.to,
      moderatedById: session.sub,
      moderatedAt: now,
      moderationNote: noteStr || null,
      // approve set publishedAt kalau belum ada; unhide tidak ubah (publishedAt
      // tetap timestamp ACTIVE pertama).
      publishedAt: action === "approve" && !post.publishedAt ? now : post.publishedAt,
    },
    select: {
      id: true,
      status: true,
      moderatedAt: true,
      moderationNote: true,
      publishedAt: true,
    },
  });

  // Notify the post author via push + notification center. Fire-and-forget
  // by design — Notification helper swallows its own errors so a failure
  // here can never roll back the moderation transition the admin just made.
  void sendFeedModerationNotification({
    postId,
    action: action as ModerationAction,
    note: noteStr || null,
  });

  // Storage cleanup. Reject + Hide free the video + thumbnail from
  // UploadThing since the post is no longer publicly visible. NOTE: unhide
  // after hide will leave a broken video URL — unhide should be reserved
  // for the same-day "oops" case before this cleanup batch lands. If you
  // need a reversible soft-hide, narrow this to only `action === "reject"`.
  if (action === "reject" || action === "hide") {
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

  // Fetch the asset URLs before the row is gone — Prisma cascade-deletes
  // FeedComment / FeedLike / FeedReport rows automatically, and we follow
  // up by also freeing the linked video + thumbnail from UploadThing.
  const existing = await prisma.feedPost.findUnique({
    where: { id: postId },
    select: { id: true, videoUrl: true, thumbnailUrl: true },
  });
  if (!existing) {
    return NextResponse.json({ error: "Post tidak ditemukan." }, { status: 404 });
  }

  await prisma.feedPost.delete({ where: { id: postId } });

  // Storage cleanup — fire-and-forget so a UploadThing outage can't fail
  // a delete that already removed the DB row.
  void deleteFeedAssets({
    videoUrl: existing.videoUrl,
    thumbnailUrl: existing.thumbnailUrl,
    context: `delete ${postId}`,
  });

  return NextResponse.json({ ok: true });
}
