import type { Prisma } from "@prisma/client";

export type FeedLikeIntent = boolean | "toggle";

export type FeedLikeStateStore = {
  hasLike(): Promise<boolean>;
  createLike(): Promise<void>;
  deleteLike(): Promise<void>;
  countLikes(): Promise<number>;
  readLikeCount?(): Promise<number>;
  writeLikeCount(count: number): Promise<void>;
};

export type FeedLikeStateResult = {
  liked: boolean;
  likeCount: number;
  changed: boolean;
};

export type FeedCommentLikeVisibility = {
  isHidden: boolean;
  deletedAt: Date | null;
  parent?: {
    isHidden: boolean;
    deletedAt: Date | null;
  } | null;
};

export function isFeedCommentLikeable(
  comment: FeedCommentLikeVisibility
): boolean {
  return !comment.isHidden && !comment.deletedAt && !comment.parent?.isHidden;
}

type FeedInteractionActorLockClient = Pick<
  Prisma.TransactionClient,
  "$queryRaw"
>;

/**
 * Keep account deletion and engagement writes on one lock order:
 * User -> FeedPost. FOR KEY SHARE permits concurrent activity by the same
 * member but conflicts with deleting/updating that account row.
 */
export async function lockFeedInteractionActor(
  db: FeedInteractionActorLockClient,
  userId: string
): Promise<boolean> {
  const users = await db.$queryRaw<Array<{ id: string }>>`
    SELECT "id"
    FROM "User"
    WHERE "id" = ${userId}
    FOR KEY SHARE
  `;
  return users.length > 0;
}

/**
 * Reconcile one viewer/target pair while the caller holds the target lock.
 * The relation table is canonical; the denormalized counter is repaired from
 * its exact count on every write so retries cannot double-flip or go negative.
 */
export async function reconcileFeedLikeState(
  store: FeedLikeStateStore,
  intent: FeedLikeIntent
): Promise<FeedLikeStateResult> {
  const previouslyLiked = await store.hasLike();
  const liked = intent === "toggle" ? !previouslyLiked : intent;

  if (liked && !previouslyLiked) {
    await store.createLike();
  } else if (!liked && previouslyLiked) {
    await store.deleteLike();
  }

  const likeCount = Math.max(0, await store.countLikes());
  const storedLikeCount = await store.readLikeCount?.();
  if (
    liked !== previouslyLiked ||
    storedLikeCount === undefined ||
    storedLikeCount !== likeCount
  ) {
    await store.writeLikeCount(likeCount);
  }
  return {
    liked,
    likeCount,
    changed: liked !== previouslyLiked,
  };
}
