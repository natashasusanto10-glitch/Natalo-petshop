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
 *   - Reply tetap tersimpan untuk audit, tetapi thread parent yang dihapus
 *     tidak dikirim ke query publik
 *
 * Idempotent: kalau komentar udah di-delete sebelumnya, return 200
 * dengan alreadyDeleted=true. Cegah error toast saat double-tap.
 *
 * FeedPost.commentCount menghitung parent + reply yang masih terlihat.
 * Setelah delete, counter direkonsiliasi dari database di dalam lock post.
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
    const post = await prisma.feedPost.findUnique({
      where: { id: comment.postId },
      select: { commentCount: true },
    });
    return NextResponse.json({
      ok: true,
      alreadyDeleted: true,
      commentId: comment.id,
      commentCount: post?.commentCount ?? 0,
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

  // Lock per post membuat delete parent/reply dan create paralel terserialisasi.
  // Recount authoritative mencegah double decrement dan reply dari parent
  // terhapus ikut tampil di counter.
  const commentCount = await prisma.$transaction(async (tx) => {
    await tx.$queryRaw`
      SELECT "id" FROM "FeedPost"
      WHERE "id" = ${comment.postId}
      FOR UPDATE
    `;
    const current = await tx.feedComment.findUnique({
      where: { id: commentId },
      select: { deletedAt: true },
    });
    if (!current || current.deletedAt) {
      const post = await tx.feedPost.findUnique({
        where: { id: comment.postId },
        select: { commentCount: true },
      });
      return post?.commentCount ?? 0;
    }
    await tx.feedComment.update({
      where: { id: commentId },
      data: { deletedAt: new Date() },
    });
    const visibleCount = await tx.feedComment.count({
      where: {
        postId: comment.postId,
        deletedAt: null,
        isHidden: false,
        OR: [
          { parentCommentId: null },
          { parent: { deletedAt: null, isHidden: false } },
        ],
      },
    });
    await tx.feedPost.update({
      where: { id: comment.postId },
      data: { commentCount: visibleCount },
    });
    return visibleCount;
  });

  return NextResponse.json({
    ok: true,
    commentId: comment.id,
    commentCount,
    deletedBy: isAuthor ? "author" : "admin",
  });
}
