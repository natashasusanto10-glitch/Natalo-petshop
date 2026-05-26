-- Timestamp untuk track kapan user dapat H-3 reminder push.
-- Cron /api/cron/order-confirm-reminder set field ini setelah push
-- sukses, supaya tidak kirim duplikat reminder di run berikutnya.

-- AlterTable
ALTER TABLE "Order" ADD COLUMN "notifiedConfirmReminderAt" TIMESTAMP(3);
