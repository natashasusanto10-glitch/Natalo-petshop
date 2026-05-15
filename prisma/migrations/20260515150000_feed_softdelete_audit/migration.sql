-- Feed soft-delete + moderation audit trail.
--
-- 1. FeedPost.deletedAt — nullable timestamp. Existing rows stay non-deleted
--    (NULL). Feed listing queries already filter by status; adding a
--    deletedAt IS NULL guard is the soft-delete invariant for new code.
-- 2. FeedModerationLog — append-only audit table. One row per admin action
--    (approve/reject/hide/unhide/delete/restore). Keeps history even after
--    the post is hard-deleted (onDelete: Cascade keeps the audit gone too
--    once we truly purge; intentional — restore won't bring back the row).

ALTER TABLE "FeedPost" ADD COLUMN "deletedAt" TIMESTAMP(3);

CREATE INDEX "FeedPost_deletedAt_idx" ON "FeedPost"("deletedAt");

CREATE TABLE "FeedModerationLog" (
    "id" TEXT NOT NULL,
    "postId" TEXT NOT NULL,
    "actorId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "fromStatus" TEXT,
    "toStatus" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FeedModerationLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "FeedModerationLog_postId_createdAt_idx" ON "FeedModerationLog"("postId", "createdAt");
CREATE INDEX "FeedModerationLog_actorId_createdAt_idx" ON "FeedModerationLog"("actorId", "createdAt");

ALTER TABLE "FeedModerationLog" ADD CONSTRAINT "FeedModerationLog_postId_fkey"
    FOREIGN KEY ("postId") REFERENCES "FeedPost"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "FeedModerationLog" ADD CONSTRAINT "FeedModerationLog_actorId_fkey"
    FOREIGN KEY ("actorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
