-- Voucher slot model for Natalo checkout (IDEMPOTENT VERSION).
-- 1 public free-shipping + 1 public product discount + 1 loyalty claim
-- + 1 private/manual code.
--
-- All statements use IF NOT EXISTS / DO blocks supaya re-run aman
-- saat production DB sudah punya beberapa column/type (mis. dari
-- manual SQL apply sebelum migration file di-commit).

-- Enum types — idempotent via DO block (CREATE TYPE tidak support IF NOT EXISTS)
DO $$ BEGIN
  CREATE TYPE "VoucherType" AS ENUM (
    'PUBLIC_FREE_SHIPPING',
    'PUBLIC_PRODUCT_DISCOUNT',
    'LOYALTY_POINT_CLAIM',
    'PRIVATE_MANUAL_CODE'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "VoucherVisibility" AS ENUM (
    'PUBLIC',
    'PRIVATE',
    'USER_OWNED'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "VoucherDiscountType" AS ENUM (
    'FIXED_AMOUNT',
    'PERCENTAGE'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE "VoucherDiscountScope" AS ENUM (
    'PRODUCT',
    'SHIPPING'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- Voucher columns — IF NOT EXISTS (PostgreSQL 9.6+ supports it)
ALTER TABLE "Voucher"
  ADD COLUMN IF NOT EXISTS "name" TEXT,
  ADD COLUMN IF NOT EXISTS "maxDiscountAmount" INTEGER,
  ADD COLUMN IF NOT EXISTS "usageLimitPerUser" INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS "type" "VoucherType" NOT NULL DEFAULT 'PUBLIC_PRODUCT_DISCOUNT',
  ADD COLUMN IF NOT EXISTS "visibility" "VoucherVisibility" NOT NULL DEFAULT 'PUBLIC',
  ADD COLUMN IF NOT EXISTS "discountType" "VoucherDiscountType" NOT NULL DEFAULT 'FIXED_AMOUNT',
  ADD COLUMN IF NOT EXISTS "discountScope" "VoucherDiscountScope" NOT NULL DEFAULT 'PRODUCT',
  ADD COLUMN IF NOT EXISTS "eligibleUserIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN IF NOT EXISTS "eligibleProductIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN IF NOT EXISTS "eligibleCategoryIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

-- Backfill default values — guard agar tidak overwrite manual changes.
-- COALESCE name supaya kalau sudah ada nama manual, tidak ke-replace.
UPDATE "Voucher"
SET
  "type" = CASE
    WHEN "sourceType" = 'SELLER_MANUAL' THEN 'PRIVATE_MANUAL_CODE'::"VoucherType"
    WHEN "userId" IS NOT NULL THEN 'LOYALTY_POINT_CLAIM'::"VoucherType"
    ELSE 'PUBLIC_PRODUCT_DISCOUNT'::"VoucherType"
  END,
  "visibility" = CASE
    WHEN "sourceType" = 'SELLER_MANUAL' THEN 'PRIVATE'::"VoucherVisibility"
    WHEN "userId" IS NOT NULL THEN 'USER_OWNED'::"VoucherVisibility"
    ELSE 'PUBLIC'::"VoucherVisibility"
  END,
  "discountType" = CASE
    WHEN "discountPercent" IS NOT NULL THEN 'PERCENTAGE'::"VoucherDiscountType"
    ELSE 'FIXED_AMOUNT'::"VoucherDiscountType"
  END,
  "discountScope" = 'PRODUCT'::"VoucherDiscountScope",
  "name" = COALESCE("name", "description", "code")
WHERE "name" IS NULL OR "type" = 'PUBLIC_PRODUCT_DISCOUNT'::"VoucherType";

-- Order voucher slot columns
ALTER TABLE "Order"
  ADD COLUMN IF NOT EXISTS "freeShippingVoucherCode" TEXT,
  ADD COLUMN IF NOT EXISTS "productVoucherCode" TEXT,
  ADD COLUMN IF NOT EXISTS "loyaltyVoucherCode" TEXT,
  ADD COLUMN IF NOT EXISTS "privateVoucherCode" TEXT,
  ADD COLUMN IF NOT EXISTS "productDiscount" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "shippingDiscount" INTEGER NOT NULL DEFAULT 0;

-- Voucher usage tracking table
CREATE TABLE IF NOT EXISTS "VoucherUsage" (
  "id" TEXT NOT NULL,
  "voucherId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "orderId" TEXT NOT NULL,
  "discountAmount" INTEGER NOT NULL DEFAULT 0,
  "voucherType" TEXT NOT NULL,
  "usedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "VoucherUsage_pkey" PRIMARY KEY ("id")
);

-- Indexes — CREATE INDEX supports IF NOT EXISTS
CREATE UNIQUE INDEX IF NOT EXISTS "VoucherUsage_voucherId_orderId_key"
  ON "VoucherUsage"("voucherId", "orderId");
CREATE INDEX IF NOT EXISTS "VoucherUsage_voucherId_idx" ON "VoucherUsage"("voucherId");
CREATE INDEX IF NOT EXISTS "VoucherUsage_userId_idx" ON "VoucherUsage"("userId");
CREATE INDEX IF NOT EXISTS "VoucherUsage_orderId_idx" ON "VoucherUsage"("orderId");
CREATE INDEX IF NOT EXISTS "Voucher_type_visibility_idx" ON "Voucher"("type", "visibility");
CREATE INDEX IF NOT EXISTS "Voucher_discountScope_idx" ON "Voucher"("discountScope");

-- Foreign keys — DO block since ADD CONSTRAINT tidak support IF NOT EXISTS
DO $$ BEGIN
  ALTER TABLE "VoucherUsage"
    ADD CONSTRAINT "VoucherUsage_voucherId_fkey"
    FOREIGN KEY ("voucherId") REFERENCES "Voucher"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  ALTER TABLE "VoucherUsage"
    ADD CONSTRAINT "VoucherUsage_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  ALTER TABLE "VoucherUsage"
    ADD CONSTRAINT "VoucherUsage_orderId_fkey"
    FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;
