-- Idempotent — bisa re-run aman saat type/column sudah ada.
DO $$ BEGIN
  CREATE TYPE "VoucherUserUsageLimitPeriod" AS ENUM ('NONE', 'LIFETIME', 'DAY', 'WEEK', 'MONTH');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

ALTER TABLE "Voucher"
ADD COLUMN IF NOT EXISTS "usageLimitPeriod" "VoucherUserUsageLimitPeriod" NOT NULL DEFAULT 'LIFETIME';

-- Backfill: existing public CUSTOMER vouchers tidak limit per user.
-- Guard: hanya update jika usageLimitPeriod masih default LIFETIME +
-- record matches criteria. Re-run aman karena WHERE filter.
UPDATE "Voucher"
SET "usageLimitPeriod" = 'NONE',
    "usageLimitPerUser" = 0
WHERE "userId" IS NULL
  AND "sourceType" = 'CUSTOMER'
  AND "kind" IN ('PRODUCT_DISCOUNT', 'FREE_SHIPPING')
  AND "usageLimitPeriod" = 'LIFETIME';
