/**
 * POST /api/feed/comments/[id]/like   - legacy toggle
 * PUT /api/feed/comments/[id]/like    - desired state: liked
 * DELETE /api/feed/comments/[id]/like - desired state: unliked
 */
import { after, NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { sendCommentLikeNotification } from "@/lib/feed/activity-notifications";
import {
  isFeedCommentLikeable,
  lockFeedInteractionActor,
  reconcileFeedLikeState,
  type FeedLikeIntent,
} from "@/lib/feed/like-state";

type RouteContext = { params: Promise<{ id: string }> };

async function handleCommentLike(
  request: NextRequest,
  { params }: RouteContext,
  intent: FeedLikeIntent,
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Login dulu" }, { status: 401 });
  }

  const { id: commentId } = await params;
  if (!commentId) {
    return NextResponse.json(
      { error: "Comment ID required" },
      { status: 400 },
    );
  }

  const locator = await prisma.feedComment
    .findUnique({
      where: { id: commentId },
      select: { postId: true },
    })
    .catch(() => null);
  if (!locator) {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan" },
      { status: 404 },
    );
  }

  const result = await prisma.$transaction(async (tx) => {
    const actorAvailable = await lockFeedInteractionActor(tx, session.sub);
    if (!actorAvailable) return { kind: "account-unavailable" } as const;

    const lockedPosts = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT "id"
      FROM "FeedPost"
      WHERE "id" = ${locator.postId}
      FOR UPDATE
    `;
    if (lockedPosts.length === 0) return null;

    const post = await tx.feedPost.findUnique({
      where: { id: locator.postId },
      select: { status: true, deletedAt: true },
    });
    const comment = await tx.feedComment.findUnique({
      where: { id: commentId },
      select: {
        isHidden: true,
        deletedAt: true,
        authorId: true,
        postId: true,
        likeCount: true,
        parent: { select: { isHidden: true, deletedAt: true } },
      },
    });
    if (
      !post ||
      post.status !== "ACTIVE" ||
      post.deletedAt ||
      !comment ||
      comment.postId !== locator.postId ||
      !isFeedCommentLikeable(comment)
    ) {
      return null;
    }

    const state = await reconcileFeedLikeState(
      {
        async hasLike() {
          const like = await tx.feedCommentLike.findUnique({
            where: {
              userId_commentId: { userId: session.sub, commentId },
            },
            select: { userId: true },
          });
          return Boolean(like);
        },
        async createLike() {
          await tx.feedCommentLike.upsert({
            where: {
              userId_commentId: { userId: session.sub, commentId },
            },
            create: { userId: session.sub, commentId },
            update: {},
          });
        },
        async deleteLike() {
          await tx.feedCommentLike.deleteMany({
            where: { userId: session.sub, commentId },
          });
        },
        countLikes() {
          return tx.feedCommentLike.count({ where: { commentId } });
        },
        async readLikeCount() {
          return comment.likeCount;
        },
        async writeLikeCount(likeCount) {
          await tx.feedComment.update({
            where: { id: commentId },
            data: { likeCount },
          });
        },
      },
      intent,
    );
    return {
      kind: "state",
      ...state,
      postId: comment.postId,
      commentAuthorId: comment.authorId,
    } as const;
  });

  if (result?.kind === "account-unavailable") {
    return NextResponse.json({ error: "Sesi tidak berlaku" }, { status: 401 });
  }
  if (!result) {
    return NextResponse.json(
      { error: "Komentar tidak ditemukan" },
      { status: 404 },
    );
  }

  if (result.changed && result.liked) {
    after(() =>
      sendCommentLikeNotification({
        commentId,
        postId: result.postId,
        commentAuthorId: result.commentAuthorId,
        actorUserId: session.sub,
        likeCount: result.likeCount,
      }),
    );
  }

  return NextResponse.json({
    ok: true,
    liked: result.liked,
    likeCount: result.likeCount,
  });
}

export function POST(request: NextRequest, context: RouteContext) {
  return handleCommentLike(request, context, "toggle");
}

export function PUT(request: NextRequest, context: RouteContext) {
  return handleCommentLike(request, context, true);
}

export function DELETE(request: NextRequest, context: RouteContext) {
  return handleCommentLike(request, context, false);
}
