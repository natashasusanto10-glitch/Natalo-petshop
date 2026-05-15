-- Denormalized share counter on FeedPost. Incremented by
-- POST /api/feed/posts/[id]/share after the native share sheet resolves
-- successfully (cancel / fail do not increment). Existing rows default
-- to 0, no backfill needed.

ALTER TABLE "FeedPost" ADD COLUMN "shareCount" INTEGER NOT NULL DEFAULT 0;
