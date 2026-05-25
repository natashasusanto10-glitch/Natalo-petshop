-- Cancellation request fields untuk customer-initiated cancel after payment.
-- User boleh cancel instant kalau belum bayar; kalau sudah PAID, request
-- masuk pending → admin Approve (jalankan refund) atau Reject.

-- AlterTable
ALTER TABLE "Order" ADD COLUMN "cancellationRequestStatus" TEXT;
ALTER TABLE "Order" ADD COLUMN "cancellationReason" TEXT;
ALTER TABLE "Order" ADD COLUMN "cancellationRequestedAt" TIMESTAMP(3);
ALTER TABLE "Order" ADD COLUMN "cancellationRespondedAt" TIMESTAMP(3);
ALTER TABLE "Order" ADD COLUMN "cancellationRespondedByAdminId" TEXT;
ALTER TABLE "Order" ADD COLUMN "cancellationRejectReason" TEXT;

-- CreateIndex (untuk admin filter "Pending Cancellation Requests").
CREATE INDEX "Order_cancellationRequestStatus_idx" ON "Order"("cancellationRequestStatus");
