-- Migration: Add Product.flashSaleEndsAt untuk Flash Sale Countdown (Hybrid A+B).
-- Date: 2026-05-20
--
-- Tambah field opsional `flashSaleEndsAt` di Product:
--   - NULL  → produk masuk Flash Sale section HANYA kalau discount >= 20%
--             (auto-include via threshold).
--   - !NULL → admin explicit tag, SELALU masuk Flash Sale apapun %-nya,
--             pakai countdown sampai timestamp ini. Setelah lewat, query
--             otomatis filter out (auto-cleanup zero-ops).
--
-- Idempotent: IF NOT EXISTS untuk ADD COLUMN + CREATE INDEX.

ALTER TABLE "Product"
  ADD COLUMN IF NOT EXISTS "flashSaleEndsAt" TIMESTAMP(3);

-- Index untuk getFlashSaleProducts() query yang filter by:
--   flashSaleEndsAt > now() AND isActive = true AND discountPrice IS NOT NULL
-- + sort by flashSaleEndsAt ASC NULLS LAST (expiring soon first).
CREATE INDEX IF NOT EXISTS "Product_flashSaleEndsAt_idx"
  ON "Product" ("flashSaleEndsAt");
