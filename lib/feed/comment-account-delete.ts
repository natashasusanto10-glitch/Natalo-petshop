import { Prisma } from "@prisma/client";

type AccountDeleteFeedClient = Pick<
  Prisma.TransactionClient,
  | "feedComment"
  | "feedLike"
  | "feedCommentLike"
  | "$queryRaw"
  | "$executeRaw"
>;

export type AccountDeleteFeedImpact = {
  commentPostIds: string[];
  likedPostIds: string[];
  likedCommentIds: string[];
};

const emptyImpact = (): AccountDeleteFeedImpact => ({
  commentPostIds: [],
  likedPostIds: [],
  likedCommentIds: [],
});

/**
 * Freezes the account before reading its feed impact. Comment/like inserts
 * need a foreign-key KEY SHARE lock on User, so this FOR UPDATE prevents a
 * new engagement from committing between the impact snapshot and cascade.
 * Every surviving FeedPost is then locked in stable order to match normal
 * feed mutation routes and avoid cross-post deadlocks.
 */
export async function prepareFeedStateForAccountDeletion({
  db,
  userId,
}: {
  db: AccountDeleteFeedClient;
  userId: string;
}): Promise<AccountDeleteFeedImpact> {
  const users = await db.$queryRaw<Array<{ id: string }>>(Prisma.sql`
    SELECT "id"
    FROM "User"
    WHERE "id" = ${userId}
    FOR UPDATE
  `);
  if (users.length === 0) return emptyImpact();

  const authoredComments = await db.feedComment.findMany({
    where: {
      authorId: userId,
      post: { authorId: { not: userId } },
    },
    distinct: ["postId"],
    select: { postId: true },
  });
  const postLikes = await db.feedLike.findMany({
    where: {
      userId,
      post: { authorId: { not: userId } },
    },
    select: { postId: true },
  });
  const commentLikes = await db.feedCommentLike.findMany({
    where: {
      userId,
      comment: {
        authorId: { not: userId },
        post: { authorId: { not: userId } },
      },
    },
    select: {
      commentId: true,
      comment: { select: { postId: true } },
    },
  });

  const impact: AccountDeleteFeedImpact = {
    commentPostIds: [
      ...new Set(authoredComments.map((row) => row.postId)),
    ].sort(),
    likedPostIds: [...new Set(postLikes.map((row) => row.postId))].sort(),
    likedCommentIds: [
      ...new Set(commentLikes.map((row) => row.commentId)),
    ].sort(),
  };
  const postIds = [
    ...new Set([
      ...impact.commentPostIds,
      ...impact.likedPostIds,
      ...commentLikes.map((row) => row.comment.postId),
    ]),
  ].sort();
  if (postIds.length > 0) {
    await db.$queryRaw<Array<{ id: string }>>(Prisma.sql`
      SELECT "id"
      FROM "FeedPost"
      WHERE "id" IN (${Prisma.join(postIds)})
      ORDER BY "id"
      FOR UPDATE
    `);
  }

  return impact;
}

/** Rebuild every denormalized feed counter affected by the User cascade. */
export async function reconcileFeedStateAfterAccountHardDelete({
  db,
  impact,
}: {
  db: AccountDeleteFeedClient;
  impact: AccountDeleteFeedImpact;
}): Promise<void> {
  if (impact.commentPostIds.length > 0) {
    await db.$executeRaw(Prisma.sql`
      UPDATE "FeedPost" AS post
      SET "commentCount" = (
        SELECT COUNT(*)::INTEGER
        FROM "FeedComment" AS comment
        LEFT JOIN "FeedComment" AS parent
          ON parent."id" = comment."parentCommentId"
        WHERE comment."postId" = post."id"
          AND comment."isHidden" = FALSE
          AND comment."deletedAt" IS NULL
          AND (
            comment."parentCommentId" IS NULL
            OR parent."isHidden" = FALSE
          )
      )
      WHERE post."id" IN (${Prisma.join(impact.commentPostIds)})
    `);
  }

  if (impact.likedPostIds.length > 0) {
    await db.$executeRaw(Prisma.sql`
      UPDATE "FeedPost" AS post
      SET "likeCount" = (
        SELECT COUNT(*)::INTEGER
        FROM "FeedLike" AS reaction
        WHERE reaction."postId" = post."id"
      )
      WHERE post."id" IN (${Prisma.join(impact.likedPostIds)})
    `);
  }

  if (impact.likedCommentIds.length > 0) {
    // Updating FeedComment also advances syncVersion through the database
    // trigger, so mounted drawers receive the corrected count as a delta.
    await db.$executeRaw(Prisma.sql`
      UPDATE "FeedComment" AS comment
      SET "likeCount" = (
        SELECT COUNT(*)::INTEGER
        FROM "FeedCommentLike" AS reaction
        WHERE reaction."commentId" = comment."id"
      )
      WHERE comment."id" IN (${Prisma.join(impact.likedCommentIds)})
    `);
  }
}
