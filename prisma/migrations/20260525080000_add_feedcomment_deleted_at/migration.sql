-- Self-delete soft marker untuk FeedComment.
-- Pattern berbeda dari isHidden (admin moderation):
--   isHidden = admin hide konten yang melanggar
--   deletedAt = user hapus komentar mereka sendiri

-- AlterTable
ALTER TABLE "FeedComment" ADD COLUMN "deletedAt" TIMESTAMP(3);
