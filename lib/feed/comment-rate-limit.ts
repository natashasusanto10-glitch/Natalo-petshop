import type { Prisma } from "@prisma/client";
import { readDatabaseClock } from "./comment-sync";

export const COMMENT_RATE_LIMIT_PER_WINDOW = 10;
export const COMMENT_RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000;

type FeedCommentRateLimitClient = Pick<
  Prisma.TransactionClient,
  "feedComment" | "$queryRaw"
>;

export type FeedCommentRateLimitResult = {
  limited: boolean;
  recentCount: number;
  retryAfterMs: number;
};

/**
 * Serialize rate-limit checks per author inside the caller's transaction.
 * Without this lock, parallel requests can all observe the same pre-insert
 * count and bypass the limit. The namespaced hash is used only as a PostgreSQL
 * transaction-scoped advisory lock; authorization still comes from session.
 */
export async function checkFeedCommentRateLimit({
  db,
  userId,
  limit = COMMENT_RATE_LIMIT_PER_WINDOW,
  windowMs = COMMENT_RATE_LIMIT_WINDOW_MS,
}: {
  db: FeedCommentRateLimitClient;
  userId: string;
  limit?: number;
  windowMs?: number;
}): Promise<FeedCommentRateLimitResult> {
  const lockKey = `feed-comment-rate:${userId}`;
  await db.$queryRaw<Array<{ locked: number }>>`
    SELECT 1 AS "locked"
    FROM (
      SELECT pg_advisory_xact_lock(hashtextextended(${lockKey}, 0))
    ) AS "comment_rate_lock"
  `;

  const now = await readDatabaseClock(db);
  const boundedWindowMs = Math.max(0, windowMs);
  const recentCount = await db.feedComment.count({
    where: {
      authorId: userId,
      createdAt: { gte: new Date(now.getTime() - boundedWindowMs) },
    },
  });

  return {
    limited: recentCount >= Math.max(0, limit),
    recentCount,
    retryAfterMs: boundedWindowMs,
  };
}
