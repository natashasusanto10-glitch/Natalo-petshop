CREATE TYPE "VoucherUserUsageLimitPeriod" AS ENUM ('NONE', 'LIFETIME', 'DAY', 'WEEK', 'MONTH');

ALTER TABLE "Voucher"
ADD COLUMN "usageLimitPeriod" "VoucherUserUsageLimitPeriod" NOT NULL DEFAULT 'LIFETIME';

UPDATE "Voucher"
SET "usageLimitPeriod" = 'NONE',
    "usageLimitPerUser" = 0
WHERE "userId" IS NULL
  AND "sourceType" = 'CUSTOMER'
  AND "kind" IN ('PRODUCT_DISCOUNT', 'FREE_SHIPPING');
