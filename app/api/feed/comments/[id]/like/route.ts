/**
 * POST /api/feed/comments/[id]/like
 *
 * Toggle like comment — pattern identik dengan post like (transaction,
 * idempotent dari sisi UI). Spec 10.8 — optimistic update.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Login dulu" }, { status: 401 });
  }

  const { id: commentId } = await params;
  if (!commentId) {
    return NextResponse.json({ error: "Comment ID required" }, { status: 400 });
  }

  const comment = await prisma.feedComment
    .findUnique({
      where: { id: commentId },
      select: { id: true, isHidden: true },
    })
    .catch(() => null);
  if (!comment || comment.isHidden) {
    return NextResponse.json({ error: "Komentar tidak ditemukan" }, { status: 404 });
  }

  const result = await prisma.$transaction(async (tx) => {
    const existing = await tx.feedCommentLike.findUnique({
      where: { userId_commentId: { userId: session.sub, commentId } },
    });

    if (existing) {
      await tx.feedCommentLike.delete({
        where: { userId_commentId: { userId: session.sub, commentId } },
      });
      const updated = await tx.feedComment.update({
        where: { id: commentId },
        data: { likeCount: { decrement: 1 } },
        select: { likeCount: true },
      });
      return { liked: false, likeCount: Math.max(0, updated.likeCount) };
    }

    await tx.feedCommentLike.create({
      data: { userId: session.sub, commentId },
    });
    const updated = await tx.feedComment.update({
      where: { id: commentId },
      data: { likeCount: { increment: 1 } },
      select: { likeCount: true },
    });
    return { liked: true, likeCount: updated.likeCount };
  });

  return NextResponse.json({ ok: true, ...result });
}
