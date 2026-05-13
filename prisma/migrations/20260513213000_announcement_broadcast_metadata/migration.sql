-- Metadata untuk Notification Center user:
-- - type membedakan order, promo, dan pengumuman.
-- - ctaLabel/period/status mendukung broadcast resmi dari admin.
-- Statement dibuat idempotent agar aman di environment yang sudah sebagian ter-update.

ALTER TABLE "Announcement" ADD COLUMN IF NOT EXISTS "type" TEXT NOT NULL DEFAULT 'announcement';
ALTER TABLE "Announcement" ADD COLUMN IF NOT EXISTS "ctaLabel" TEXT;
ALTER TABLE "Announcement" ADD COLUMN IF NOT EXISTS "startsAt" TIMESTAMP(3);
ALTER TABLE "Announcement" ADD COLUMN IF NOT EXISTS "endsAt" TIMESTAMP(3);
ALTER TABLE "Announcement" ADD COLUMN IF NOT EXISTS "publishedAt" TIMESTAMP(3);
ALTER TABLE "Announcement" ADD COLUMN IF NOT EXISTS "status" TEXT NOT NULL DEFAULT 'PUBLISHED';

UPDATE "Announcement"
SET "type" = 'order'
WHERE "targetUserId" IS NOT NULL AND "type" = 'announcement';

UPDATE "Announcement"
SET "publishedAt" = "createdAt"
WHERE "publishedAt" IS NULL AND "status" = 'PUBLISHED';

CREATE INDEX IF NOT EXISTS "Announcement_type_idx" ON "Announcement"("type");
CREATE INDEX IF NOT EXISTS "Announcement_status_idx" ON "Announcement"("status");
