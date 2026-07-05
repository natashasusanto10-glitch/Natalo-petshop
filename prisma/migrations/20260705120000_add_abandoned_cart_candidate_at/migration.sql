-- Tanda "pertama kali dicurigai abandoned" oleh cron abandoned-cart —
-- syarat 2-putaran-berturut sebelum kirim notifikasi. Nullable, tidak
-- perlu backfill.
ALTER TABLE "CartItem"
  ADD COLUMN IF NOT EXISTS "abandonedCandidateAt" TIMESTAMP(3);
