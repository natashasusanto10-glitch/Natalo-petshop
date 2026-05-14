/**
 * PATCH /api/admin/feed/comments/[id]
 *   Body: { action: "hide" | "unhide", reason?: string }
 *
 * DELETE /api/admin/feed/comments/[id]  — hard delete.
 *
 * Counter rules:
 * - Hide (top-level): decrement commentCount supaya badge match jumlah
 *   visible. Sebelumnya leave counter as-is → badge "10" tapi sheet
 *   render 7 (3 hidden) = confusing UX.
 * - Unhide (top-level): increment back.
 * - Delete (top-level): decrement (same as hide).
 * - Reply (parentCommentId != null): counter tidak terpengaruh (badge
 *   hanya count top-level).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";

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

  const { id: commentId } = await params;
  if (!commentId) {
    return NextResponse.json({ error: "Comment ID required" }, { status: 400 });
  }

  const body = await request.json().catch(() => ({}));
  const action = String((body as { action?: unknown }).action ?? "");
  const rawReason = (body as { reason?: unknown }).reason;
  const reason = typeof rawReason === "string" ? rawReason.trim().slice(0, 500) : "";

  if (action !== "hide" && action !== "unhide") {
    return NextResponse.json(
      { error: "Action harus 'hide' atau 'unhide'." },
      { status: 400 },
    );
  }

  const comment = await prisma.feedComment.findUnique({
    where: { id: commentId },
    select: { id: true, isHidden: true, postId: true, parentCommentId: true },
  });
  if (!comment) {
    return NextResponse.json({ error: "Komentar tidak ditemukan." }, { status: 404 });
  }
  if (action === "hide" && comment.isHidden) {
    return NextResponse.json({ error: "Komentar sudah disembunyikan." }, { status: 409 });
  }
  if (action === "unhide" && !comment.isHidden) {
    return NextResponse.json({ error: "Komentar belum disembunyikan." }, { status: 409 });
  }

  // Transaction supaya update comment + adjust counter atomic.
  const updated = await prisma.$transaction(async (tx) => {
    const comm = await tx.feedComment.update({
      where: { id: commentId },
      data: {
        isHidden: action === "hide",
        hiddenById: action === "hide" ? session.sub : null,
        hiddenAt: action === "hide" ? new Date() : null,
        hiddenReason: action === "hide" ? reason || null : null,
      },
      select: { id: true, isHidden: true, hiddenReason: true },
    });

    // Adjust commentCount hanya untuk top-level comment.
    if (comment.parentCommentId === null) {
      const delta = action === "hide" ? -1 : 1;
      await tx.feedPost.update({
        where: { id: comment.postId },
        data: { commentCount: { increment: delta } },
      });
      // Floor cleanup kalau drift.
      await tx.feedPost.updateMany({
        where: { id: comment.postId, commentCount: { lt: 0 } },
        data: { commentCount: 0 },
      });
    }

    return comm;
  });

  return NextResponse.json({ ok: true, comment: updated });
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

  const { id: commentId } = await params;
  if (!commentId) {
    return NextResponse.json({ error: "Comment ID required" }, { status: 400 });
  }

  const comment = await prisma.feedComment.findUnique({
    where: { id: commentId },
    select: { id: true, postId: true, parentCommentId: true },
  });
  if (!comment) {
    return NextResponse.json({ error: "Komentar tidak ditemukan." }, { status: 404 });
  }

  // Transaction: delete + decrement counter (hanya top-level mengikuti
  // logic POST yang increment hanya saat parentCommentId=null).
  await prisma.$transaction(async (tx) => {
    await tx.feedComment.delete({ where: { id: commentId } });
    if (comment.parentCommentId === null) {
      // Decrement, floor di 0.
      await tx.feedPost.update({
        where: { id: comment.postId },
        data: { commentCount: { decrement: 1 } },
      });
      // Floor cleanup — kalau counter drifted negative, normalize.
      await tx.feedPost.updateMany({
        where: { id: comment.postId, commentCount: { lt: 0 } },
        data: { commentCount: 0 },
      });
    }
  });

  return NextResponse.json({ ok: true });
}
