-- Bunny Stream integration. Two columns on FeedPost:
--
-- 1. videoGuid — the GUID Bunny assigns when we POST /library/.../videos.
--    NULL for existing UploadThing-backed posts. Unique index so we can
--    look up the right FeedPost from a webhook payload.
-- 2. encodingStatus — lifecycle for Bunny-encoded videos. Existing rows
--    default to "ready" because their videoUrl is a direct UploadThing
--    CDN URL that's playable immediately. New Bunny rows start as
--    "uploading", flip to "processing" once Bunny accepts the file, and
--    settle at "ready" when the webhook fires.

ALTER TABLE "FeedPost" ADD COLUMN "videoGuid" TEXT;
ALTER TABLE "FeedPost" ADD COLUMN "encodingStatus" TEXT NOT NULL DEFAULT 'ready';

CREATE UNIQUE INDEX "FeedPost_videoGuid_key" ON "FeedPost"("videoGuid");
CREATE INDEX "FeedPost_encodingStatus_idx" ON "FeedPost"("encodingStatus");
