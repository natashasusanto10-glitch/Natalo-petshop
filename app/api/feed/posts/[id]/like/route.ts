/**
 * POST /api/feed/posts/[id]/like   - legacy toggle
 * PUT /api/feed/posts/[id]/like    - desired state: liked
 * DELETE /api/feed/posts/[id]/like - desired state: unliked
 */
import { after, NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { sendLikeNotification } from "@/lib/feed/activity-notifications";
import { brandDisplayName, brandPhotoUrl } from "@/lib/social/brand-user";
import {
  lockFeedInteractionActor,
  reconcileFeedLikeState,
  type FeedLikeIntent,
} from "@/lib/feed/like-state";

type RouteContext = { params: Promise<{ id: string }> };

async function handlePostLike(
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

  const { id: postId } = await params;
  if (!postId) {
    return NextResponse.json({ error: "Post ID required" }, { status: 400 });
  }

  const result = await prisma.$transaction(async (tx) => {
    const actorAvailable = await lockFeedInteractionActor(tx, session.sub);
    if (!actorAvailable) return { kind: "account-unavailable" } as const;

    const lockedPosts = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT "id"
      FROM "FeedPost"
      WHERE "id" = ${postId}
      FOR UPDATE
    `;
    if (lockedPosts.length === 0) return null;

    const post = await tx.feedPost.findUnique({
      where: { id: postId },
      select: { status: true, deletedAt: true, likeCount: true },
    });
    if (!post || post.status !== "ACTIVE" || post.deletedAt) return null;

    const state = await reconcileFeedLikeState(
      {
        async hasLike() {
          const like = await tx.feedLike.findUnique({
            where: { userId_postId: { userId: session.sub, postId } },
            select: { userId: true },
          });
          return Boolean(like);
        },
        async createLike() {
          await tx.feedLike.upsert({
            where: { userId_postId: { userId: session.sub, postId } },
            create: { userId: session.sub, postId },
            update: {},
          });
        },
        async deleteLike() {
          await tx.feedLike.deleteMany({
            where: { userId: session.sub, postId },
          });
        },
        countLikes() {
          return tx.feedLike.count({ where: { postId } });
        },
        async readLikeCount() {
          return post.likeCount;
        },
        async writeLikeCount(likeCount) {
          await tx.feedPost.update({
            where: { id: postId },
            data: { likeCount },
          });
        },
      },
      intent,
    );
    return { kind: "state", ...state } as const;
  });

  if (result?.kind === "account-unavailable") {
    return NextResponse.json({ error: "Sesi tidak berlaku" }, { status: 401 });
  }
  if (!result) {
    return NextResponse.json(
      { error: "Post tidak ditemukan" },
      { status: 404 },
    );
  }

  if (result.changed && result.liked) {
    after(() =>
      sendLikeNotification({
        postId,
        actorUserId: session.sub,
        likeCount: result.likeCount,
      }),
    );
  }

  const recentLikes = await prisma.feedLike.findMany({
    where: { postId },
    orderBy: { createdAt: "desc" },
    take: 3,
    select: {
      user: {
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

  return NextResponse.json({
    ok: true,
    liked: result.liked,
    likeCount: result.likeCount,
    recentLikers: recentLikes.map((like) => ({
      id: like.user.id,
      name: brandDisplayName(like.user.role, like.user.name),
      username: like.user.username,
      role: like.user.role === "ADMIN" ? "ADMIN" : "CUSTOMER",
      profilePhotoUrl: brandPhotoUrl(like.user.role, like.user.profilePhotoUrl),
      avatarUrl: brandPhotoUrl(like.user.role, like.user.profilePhotoUrl),
    })),
  });
}

export function POST(request: NextRequest, context: RouteContext) {
  return handlePostLike(request, context, "toggle");
}

export function PUT(request: NextRequest, context: RouteContext) {
  return handlePostLike(request, context, true);
}

export function DELETE(request: NextRequest, context: RouteContext) {
  return handlePostLike(request, context, false);
}
