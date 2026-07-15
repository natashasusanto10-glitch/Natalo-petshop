-- Per-user feed post bookmarks. The composite primary key makes repeated
-- save requests idempotent, while the listing index supports newest-first
-- cursor pagination without scanning another user's rows.

CREATE TABLE "FeedSave" (
    "userId" TEXT NOT NULL,
    "postId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FeedSave_pkey" PRIMARY KEY ("userId", "postId")
);

CREATE INDEX "FeedSave_userId_createdAt_postId_idx"
ON "FeedSave"("userId", "createdAt", "postId");

CREATE INDEX "FeedSave_postId_idx" ON "FeedSave"("postId");

ALTER TABLE "FeedSave" ADD CONSTRAINT "FeedSave_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "FeedSave" ADD CONSTRAINT "FeedSave_postId_fkey"
FOREIGN KEY ("postId") REFERENCES "FeedPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;
