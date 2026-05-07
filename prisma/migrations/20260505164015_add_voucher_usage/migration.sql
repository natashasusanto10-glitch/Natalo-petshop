-- AlterTable
ALTER TABLE "Voucher" ADD COLUMN     "maxUsage" INTEGER,
ADD COLUMN     "usedCount" INTEGER NOT NULL DEFAULT 0;
