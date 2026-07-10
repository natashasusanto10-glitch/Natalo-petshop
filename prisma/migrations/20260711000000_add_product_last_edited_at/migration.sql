-- Kolom "kapan admin terakhir mengedit/membuat produk ini" untuk admin list
-- (urut "baru diedit" ke atas + badge). Beda dari updatedAt yang ikut berubah
-- otomatis (stok/rating/promo). Nullable, tanpa backfill — produk lama = NULL.
--
-- Idempoten (ADD COLUMN IF NOT EXISTS) supaya `prisma migrate deploy` aman
-- di DB yang mungkin sudah drift (mis. sempat `db push`), sama pola dengan
-- migration 20260710000000_add_product_video_columns.
--
-- Prisma DateTime? → TIMESTAMP(3) nullable (lihat migration
-- 20260705120000_add_abandoned_cart_candidate_at).

ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "lastEditedAt" TIMESTAMP(3);
