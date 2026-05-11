-- Announcement + AnnouncementRead — in-app notification center storage.
-- Semua statement idempotent (IF NOT EXISTS) supaya aman di prod yang
-- belum/sudah punya struktur ini.

CREATE TABLE IF NOT EXISTS "Announcement" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "url" TEXT,
    "segment" TEXT NOT NULL DEFAULT 'all',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Announcement_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "Announcement_createdAt_idx" ON "Announcement"("createdAt");
CREATE INDEX IF NOT EXISTS "Announcement_segment_idx" ON "Announcement"("segment");

CREATE TABLE IF NOT EXISTS "AnnouncementRead" (
    "userId" TEXT NOT NULL,
    "announcementId" TEXT NOT NULL,
    "readAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AnnouncementRead_pkey" PRIMARY KEY ("userId", "announcementId")
);

CREATE INDEX IF NOT EXISTS "AnnouncementRead_userId_idx" ON "AnnouncementRead"("userId");
CREATE INDEX IF NOT EXISTS "AnnouncementRead_announcementId_idx" ON "AnnouncementRead"("announcementId");

-- Foreign keys — pakai DO-block supaya idempotent (Postgres tidak punya
-- "ADD CONSTRAINT IF NOT EXISTS" sebelum v18).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'AnnouncementRead_userId_fkey'
  ) THEN
    ALTER TABLE "AnnouncementRead"
      ADD CONSTRAINT "AnnouncementRead_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'AnnouncementRead_announcementId_fkey'
  ) THEN
    ALTER TABLE "AnnouncementRead"
      ADD CONSTRAINT "AnnouncementRead_announcementId_fkey"
      FOREIGN KEY ("announcementId") REFERENCES "Announcement"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
