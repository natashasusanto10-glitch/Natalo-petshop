CREATE TYPE "VoucherKind" AS ENUM (
  'PRODUCT_DISCOUNT',
  'FREE_SHIPPING',
  'LOYALTY_CLAIM',
  'MANUAL_PRIVATE'
);

ALTER TABLE "Voucher"
ADD COLUMN "kind" "VoucherKind" NOT NULL DEFAULT 'PRODUCT_DISCOUNT';

UPDATE "Voucher"
SET "kind" = CASE
  WHEN "sourceType" = 'SELLER_MANUAL' THEN 'MANUAL_PRIVATE'::"VoucherKind"
  WHEN "userId" IS NOT NULL OR "code" LIKE 'POIN-%' THEN 'LOYALTY_CLAIM'::"VoucherKind"
  ELSE 'PRODUCT_DISCOUNT'::"VoucherKind"
END;

CREATE INDEX "Voucher_kind_idx" ON "Voucher"("kind");
