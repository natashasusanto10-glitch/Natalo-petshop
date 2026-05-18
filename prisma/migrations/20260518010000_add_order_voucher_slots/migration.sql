-- Idempotent — productVoucherCode + loyaltyVoucherCode mungkin sudah
-- ditambah di migration sebelumnya (20260517153000_voucher_slots_and_usage).
-- Pakai IF NOT EXISTS supaya re-apply aman.
ALTER TABLE "Order"
ADD COLUMN IF NOT EXISTS "productVoucherCode" TEXT,
ADD COLUMN IF NOT EXISTS "shippingVoucherCode" TEXT,
ADD COLUMN IF NOT EXISTS "loyaltyVoucherCode" TEXT;

-- Backfill productVoucherCode dari voucherCode lama. Guard WHERE supaya
-- tidak overwrite kalau migration sudah pernah jalan.
UPDATE "Order"
SET "productVoucherCode" = "voucherCode"
WHERE "voucherCode" IS NOT NULL
  AND "productVoucherCode" IS NULL;
