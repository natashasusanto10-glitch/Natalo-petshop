-- Voucher slot model for Natalo checkout:
-- 1 public free-shipping + 1 public product discount + 1 loyalty claim
-- + 1 private/manual code.

CREATE TYPE "VoucherType" AS ENUM (
  'PUBLIC_FREE_SHIPPING',
  'PUBLIC_PRODUCT_DISCOUNT',
  'LOYALTY_POINT_CLAIM',
  'PRIVATE_MANUAL_CODE'
);

CREATE TYPE "VoucherVisibility" AS ENUM (
  'PUBLIC',
  'PRIVATE',
  'USER_OWNED'
);

CREATE TYPE "VoucherDiscountType" AS ENUM (
  'FIXED_AMOUNT',
  'PERCENTAGE'
);

CREATE TYPE "VoucherDiscountScope" AS ENUM (
  'PRODUCT',
  'SHIPPING'
);

ALTER TABLE "Voucher"
  ADD COLUMN "name" TEXT,
  ADD COLUMN "maxDiscountAmount" INTEGER,
  ADD COLUMN "usageLimitPerUser" INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN "type" "VoucherType" NOT NULL DEFAULT 'PUBLIC_PRODUCT_DISCOUNT',
  ADD COLUMN "visibility" "VoucherVisibility" NOT NULL DEFAULT 'PUBLIC',
  ADD COLUMN "discountType" "VoucherDiscountType" NOT NULL DEFAULT 'FIXED_AMOUNT',
  ADD COLUMN "discountScope" "VoucherDiscountScope" NOT NULL DEFAULT 'PRODUCT',
  ADD COLUMN "eligibleUserIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN "eligibleProductIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN "eligibleCategoryIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

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
  "name" = COALESCE("description", "code");

ALTER TABLE "Order"
  ADD COLUMN "freeShippingVoucherCode" TEXT,
  ADD COLUMN "productVoucherCode" TEXT,
  ADD COLUMN "loyaltyVoucherCode" TEXT,
  ADD COLUMN "privateVoucherCode" TEXT,
  ADD COLUMN "productDiscount" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "shippingDiscount" INTEGER NOT NULL DEFAULT 0;

CREATE TABLE "VoucherUsage" (
  "id" TEXT NOT NULL,
  "voucherId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "orderId" TEXT NOT NULL,
  "discountAmount" INTEGER NOT NULL DEFAULT 0,
  "voucherType" TEXT NOT NULL,
  "usedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "VoucherUsage_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "VoucherUsage_voucherId_orderId_key"
  ON "VoucherUsage"("voucherId", "orderId");
CREATE INDEX "VoucherUsage_voucherId_idx" ON "VoucherUsage"("voucherId");
CREATE INDEX "VoucherUsage_userId_idx" ON "VoucherUsage"("userId");
CREATE INDEX "VoucherUsage_orderId_idx" ON "VoucherUsage"("orderId");
CREATE INDEX "Voucher_type_visibility_idx" ON "Voucher"("type", "visibility");
CREATE INDEX "Voucher_discountScope_idx" ON "Voucher"("discountScope");

ALTER TABLE "VoucherUsage"
  ADD CONSTRAINT "VoucherUsage_voucherId_fkey"
  FOREIGN KEY ("voucherId") REFERENCES "Voucher"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "VoucherUsage"
  ADD CONSTRAINT "VoucherUsage_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "VoucherUsage"
  ADD CONSTRAINT "VoucherUsage_orderId_fkey"
  FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;
