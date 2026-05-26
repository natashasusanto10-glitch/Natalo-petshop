/**
 * DELETE /api/feed/comments/[id]
 *
 * User-facing endpoint untuk delete komentar feed sendiri. Soft-delete
 * pattern: set FeedComment.deletedAt = now() + decrement
 * FeedPost.commentCount atomic.
 *
 * Authorization:
 *   - Author komentar (authorId == session.sub) — bisa delete kapanpun
 *   - Admin — bisa delete komentar siapa saja (pakai admin moderation
 *     PATCH `isHidden=true` untuk distinguish; tapi endpoint ini juga
 *     allow admin DELETE sebagai shortcut)
 *
 * Soft delete reasons:
 *   - Audit trail tetap ada (row tidak hilang)
 *   - Admin bisa lihat history kalau ada dispute
 *   - Reply ke komentar yg di-delete tetap visible (orphan placeholder)
 *
 * Idempotent: kalau komentar udah di-delete sebelumnya, return 200
 * dengan alreadyDeleted=true. Cegah error toast saat double-tap.
 *
 * Decrement commentCount:
 *   - Top-level comment (parentCommentId=null) → decrement
 *   - Reply (parentCommentId != null) → JANGAN decrement (per Shopee/IG
 *     pattern: replies tidak dihitung di commentCount yang main). Verify
 *     dengan POST endpoint behavior — kalau dia juga skip reply,
 *     consistent.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { assertSameOrigin } from "@/lib/csrf";

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session =
    (await getSession("ADMIN")) ?? (await getSession("CUSTOMER"));
  if (!session) {
    return NextResponse.json(
      { error: "Login dulu untuk hapus komentar." },
      { status: 401 },
    );
  }

  const { id: commentId } = await params;
  if (!commentId) {
    return NextResponse.json(
      { error: "Comment ID kosong." },
      { status: 400 },
    );
  }

  const comment = await prisma.feedComment.findUnique({
    where: { id: commentId },
    select: {
      id: true,
      authorId: true,
      postId: true,
      parentCommentId: true,
      deletedAt: true,
    },
  });
  if (!comment) {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan." },
      { status: 404 },
    );
  }

  // Idempotent — return success kalau already deleted, biar UI tidak
  // show error untuk double-tap.
  if (comment.deletedAt) {
    return NextResponse.json({
      ok: true,
      alreadyDeleted: true,
      commentId: comment.id,
    });
  }

  const isAdmin = session.role === "ADMIN";
  const isAuthor = comment.authorId === session.sub;
  if (!isAdmin && !isAuthor) {
    return NextResponse.json(
      { error: "Kamu tidak berhak menghapus komentar ini." },
      { status: 403 },
    );
  }

  // Atomic: set deletedAt + decrement commentCount (kalau top-level).
  // Reply tidak di-count di FeedPost.commentCount per existing pattern.
  await prisma.$transaction(async (tx) => {
    await tx.feedComment.update({
      where: { id: commentId },
      data: { deletedAt: new Date() },
    });
    // Decrement commentCount hanya untuk top-level.
    // Pakai conditional update — defensive supaya tidak underflow ke
    // negative kalau ada race condition / counter drift sebelumnya.
    if (comment.parentCommentId === null) {
      await tx.feedPost.updateMany({
        where: { id: comment.postId, commentCount: { gt: 0 } },
        data: { commentCount: { decrement: 1 } },
      });
    }
  });

  return NextResponse.json({
    ok: true,
    commentId: comment.id,
    deletedBy: isAuthor ? "author" : "admin",
  });
}
