-- Migration: Add PHOTO_CAROUSEL FeedPost kind + FeedMedia table
-- Date: 2026-05-20
--
-- Enables photo posts in Feed (1-8 images per post). User flow:
--   1. User tap "+" di Feed, pilih "Upload Foto"
--   2. Multi-select 1-8 foto
--   3. Preview carousel + caption + product tag
--   4. Submit → status PENDING_REVIEW
--   5. Admin approve → status ACTIVE → tampil di feed dengan
--      PageView horizontal carousel render
--
-- Existing video kind (VIDEO_ONLY, VIDEO_PRODUCT, COMMUNITY, PROMO)
-- tidak terpengaruh — video tetap stored di FeedPost.videoUrl/videoGuid.
-- FeedMedia table baru hanya populated untuk PHOTO_CAROUSEL kind.

-- 1. Tambah enum value PHOTO_CAROUSEL ke FeedPostKind
ALTER TYPE "FeedPostKind" ADD VALUE IF NOT EXISTS 'PHOTO_CAROUSEL';

-- 2. Create FeedMedia table
CREATE TABLE IF NOT EXISTS "FeedMedia" (
  "id"             TEXT NOT NULL,
  "postId"         TEXT NOT NULL,
  "mediaType"      TEXT NOT NULL DEFAULT 'image',
  "url"            TEXT NOT NULL,
  "thumbnailUrl"   TEXT,
  "uploadthingKey" TEXT,
  "sortOrder"      INTEGER NOT NULL DEFAULT 0,
  "width"          INTEGER,
  "height"         INTEGER,
  "createdAt"      TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "FeedMedia_pkey" PRIMARY KEY ("id")
);

-- 3. Foreign key — CASCADE delete saat post di-delete supaya orphan
--    media row tidak menumpuk (storage cleanup via UploadThing API harus
--    di-handle separately via lib/feed/cleanup atau cron).
ALTER TABLE "FeedMedia"
  DROP CONSTRAINT IF EXISTS "FeedMedia_postId_fkey";
ALTER TABLE "FeedMedia"
  ADD CONSTRAINT "FeedMedia_postId_fkey"
  FOREIGN KEY ("postId") REFERENCES "FeedPost"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

-- 4. Index untuk fetch media by post (ordered by sortOrder for carousel).
CREATE INDEX IF NOT EXISTS "FeedMedia_postId_sortOrder_idx"
  ON "FeedMedia" ("postId", "sortOrder");
