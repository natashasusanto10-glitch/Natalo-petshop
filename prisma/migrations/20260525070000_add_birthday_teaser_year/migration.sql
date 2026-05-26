-- Anti-spam tracker untuk birthday H-1 teaser push.
-- Set saat cron /api/cron/birthday-reminder sukses kirim push, cek
-- sebelum send supaya tidak duplicate kalau cron re-run hari sama.

-- AlterTable
ALTER TABLE "User" ADD COLUMN "lastBirthdayTeaserYear" INTEGER;
