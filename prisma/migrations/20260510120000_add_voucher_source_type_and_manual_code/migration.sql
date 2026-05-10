-- CreateEnum
CREATE TYPE "VoucherSourceType" AS ENUM ('CUSTOMER', 'SELLER_MANUAL');

-- AlterTable
ALTER TABLE "Voucher" ADD COLUMN "sourceType" "VoucherSourceType" NOT NULL DEFAULT 'CUSTOMER';

-- AlterTable
ALTER TABLE "Order" ADD COLUMN "manualVoucherCode" TEXT;
