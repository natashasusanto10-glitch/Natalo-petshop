-- AlterTable
ALTER TABLE "Voucher" ADD COLUMN     "userId" TEXT;

-- CreateIndex
CREATE INDEX "Voucher_userId_idx" ON "Voucher"("userId");
