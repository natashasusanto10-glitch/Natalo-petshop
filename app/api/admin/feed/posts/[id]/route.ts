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
    select: { id: true, status: true, publishedAt: true },
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

  // Cascade FK di schema akan otomatis hapus FeedComment, FeedLike, dll.
  const result = await prisma.feedPost
    .delete({ where: { id: postId } })
    .catch(() => null);
  if (!result) {
    return NextResponse.json({ error: "Post tidak ditemukan." }, { status: 404 });
  }

  // Note: TIDAK delete file di UploadThing storage (mahal + risiko false-delete).
  // Orphan files bisa di-GC via scheduled cleanup task nanti.

  return NextResponse.json({ ok: true });
}
