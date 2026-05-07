-- Add paymentProofUrl to Order (optional column, safe)
ALTER TABLE "Order" ADD COLUMN IF NOT EXISTS "paymentProofUrl" TEXT;

-- Add recipient column to Address (copy from recipientName, then set NOT NULL)
ALTER TABLE "Address" ADD COLUMN IF NOT EXISTS "recipient" TEXT;
UPDATE "Address" SET "recipient" = COALESCE("recipientName", '') WHERE "recipient" IS NULL;
ALTER TABLE "Address" ALTER COLUMN "recipient" SET NOT NULL;

-- Drop old Address columns that were replaced
ALTER TABLE "Address" DROP COLUMN IF EXISTS "recipientName";
ALTER TABLE "Address" DROP COLUMN IF EXISTS "city_code";
ALTER TABLE "Address" DROP COLUMN IF EXISTS "district";
ALTER TABLE "Address" DROP COLUMN IF EXISTS "district_code";
ALTER TABLE "Address" DROP COLUMN IF EXISTS "province";
ALTER TABLE "Address" DROP COLUMN IF EXISTS "province_code";
ALTER TABLE "Address" DROP COLUMN IF EXISTS "village";
ALTER TABLE "Address" DROP COLUMN IF EXISTS "village_code";

-- Drop old variant junction table (replaced by ProductVariantOption)
DROP TABLE IF EXISTS "VariantOptionOnVariant";
