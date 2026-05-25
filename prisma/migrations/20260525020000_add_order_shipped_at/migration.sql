-- shippedAt timestamp untuk track kapan order beneran ditandai SHIPPED.
-- Cron auto-confirm-delivered pakai field ini (bukan updatedAt yang
-- gampang re-trigger).

-- AlterTable
ALTER TABLE "Order" ADD COLUMN "shippedAt" TIMESTAMP(3);

-- Backfill untuk order existing yang status='SHIPPED' supaya cron tidak
-- skip mereka. Pakai updatedAt sebagai best-effort approximation
-- (admin yang tandai SHIPPED biasanya tidak touch lagi sampai customer
-- confirm receipt, jadi updatedAt ≈ shippedAt). Order non-SHIPPED tetap
-- null karena memang belum pernah dikirim.
UPDATE "Order" SET "shippedAt" = "updatedAt" WHERE "status" = 'SHIPPED';

-- CreateIndex untuk query cron WHERE status='SHIPPED' AND shippedAt < threshold.
CREATE INDEX "Order_status_shippedAt_idx" ON "Order"("status", "shippedAt");
