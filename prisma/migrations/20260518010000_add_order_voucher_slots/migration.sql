ALTER TABLE "Order"
ADD COLUMN "productVoucherCode" TEXT,
ADD COLUMN "shippingVoucherCode" TEXT,
ADD COLUMN "loyaltyVoucherCode" TEXT;

UPDATE "Order"
SET "productVoucherCode" = "voucherCode"
WHERE "voucherCode" IS NOT NULL
  AND "productVoucherCode" IS NULL;
