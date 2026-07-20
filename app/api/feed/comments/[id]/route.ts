/**
 * DELETE /api/feed/comments/[id]
 *
 * Soft-delete a comment owned by the viewer. Admins retain the existing
 * shortcut permission. The post row serializes create/delete/sync snapshots,
 * and the visible counter is reconciled from the database after every call.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { assertSameOrigin } from "@/lib/csrf";
import {
  countedFeedCommentWhere,
  readDatabaseClock,
} from "@/lib/feed/comment-sync";
import { getFeedCommentDetail } from "@/lib/feed/queries";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id: commentId } = await params;
  if (!commentId) {
    return NextResponse.json({ error: "Comment ID kosong." }, { status: 400 });
  }

  const session = await getSession();
  const result = await getFeedCommentDetail({
    commentId,
    viewerUserId: session?.sub ?? null,
  });

  if (result.status === "not-found") {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan", reason: "comment_deleted" },
      { status: 404 }
    );
  }
  if (result.status === "post-gone") {
    return NextResponse.json(
      { error: "Postingan sudah dihapus", reason: "post_deleted" },
      { status: 404 }
    );
  }
  return NextResponse.json({
    ok: true,
    comment: result.comment,
    postId: result.comment.postId,
  });
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = (await getSession("ADMIN")) ?? (await getSession("CUSTOMER"));
  if (!session) {
    return NextResponse.json(
      { error: "Login dulu untuk hapus komentar." },
      { status: 401 }
    );
  }

  const { id: commentId } = await params;
  if (!commentId) {
    return NextResponse.json({ error: "Comment ID kosong." }, { status: 400 });
  }

  const comment = await prisma.feedComment.findUnique({
    where: { id: commentId },
    select: {
      id: true,
      authorId: true,
      postId: true,
      deletedAt: true,
    },
  });
  if (!comment) {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan." },
      { status: 404 }
    );
  }

  const isAdmin = session.role === "ADMIN";
  const isAuthor = comment.authorId === session.sub;
  if (!isAdmin && !isAuthor) {
    return NextResponse.json(
      { error: "Kamu tidak berhak menghapus komentar ini." },
      { status: 403 }
    );
  }

  const result = await prisma.$transaction(async (tx) => {
    const lockedPosts = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT "id"
      FROM "FeedPost"
      WHERE "id" = ${comment.postId}
      FOR UPDATE
    `;
    if (lockedPosts.length === 0) return null;

    const current = await tx.feedComment.findUnique({
      where: { id: commentId },
      select: {
        authorId: true,
        postId: true,
        deletedAt: true,
        isHidden: true,
      },
    });
    if (!current || current.postId !== comment.postId) return null;
    if (session.role !== "ADMIN" && current.authorId !== session.sub) {
      return { forbidden: true } as const;
    }

    const moderationDelete =
      session.role === "ADMIN" && current.authorId !== session.sub;
    const alreadyDeleted = Boolean(current.deletedAt);
    if (!alreadyDeleted || (moderationDelete && !current.isHidden)) {
      const deletedAt = await readDatabaseClock(tx);
      await tx.feedComment.update({
        where: { id: commentId },
        data: moderationDelete
          ? {
              deletedAt: current.deletedAt ?? deletedAt,
              isHidden: true,
              hiddenById: session.sub,
              hiddenAt: deletedAt,
              hiddenReason: "Dihapus moderator",
            }
          : { deletedAt },
      });
    }

    const commentCount = await tx.feedComment.count({
      where: countedFeedCommentWhere(comment.postId),
    });
    await tx.feedPost.update({
      where: { id: comment.postId },
      data: { commentCount },
    });
    return { forbidden: false, alreadyDeleted, commentCount } as const;
  });

  if (!result) {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan." },
      { status: 404 }
    );
  }
  if (result.forbidden) {
    return NextResponse.json(
      { error: "Kamu tidak berhak menghapus komentar ini." },
      { status: 403 }
    );
  }
  if (result.alreadyDeleted) {
    return NextResponse.json({
      ok: true,
      alreadyDeleted: true,
      commentId: comment.id,
      commentCount: result.commentCount,
    });
  }

  return NextResponse.json({
    ok: true,
    commentId: comment.id,
    commentCount: result.commentCount,
    deletedBy: isAuthor ? "author" : "admin",
  });
}
