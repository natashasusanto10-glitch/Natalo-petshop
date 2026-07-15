CREATE TYPE "PaymentProofStatus" AS ENUM (
  'NOT_UPLOADED',
  'PENDING_REVIEW',
  'VERIFIED',
  'REJECTED',
  'REPLACED'
);

ALTER TABLE "Order"
  ADD COLUMN "paymentProofUploadedAt" TIMESTAMP(3),
  ADD COLUMN "paymentProofVersion" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "paymentProofStatus" "PaymentProofStatus" NOT NULL DEFAULT 'NOT_UPLOADED',
  ADD COLUMN "paymentProofReviewedAt" TIMESTAMP(3),
  ADD COLUMN "paymentProofReviewedBy" TEXT,
  ADD COLUMN "paymentProofRejectReason" TEXT;

-- Existing proof URLs predate audit metadata. Treat them as version 1 waiting
-- for review and retain the original Order.createdAt only as a safe fallback.
UPDATE "Order"
SET
  "paymentProofVersion" = 1,
  "paymentProofStatus" = 'PENDING_REVIEW',
  "paymentProofUploadedAt" = COALESCE("updatedAt", "createdAt")
WHERE "paymentProofUrl" IS NOT NULL;

CREATE TABLE "OrderPaymentProof" (
  "id" TEXT NOT NULL,
  "orderId" TEXT NOT NULL,
  "version" INTEGER NOT NULL,
  "url" TEXT NOT NULL,
  "status" "PaymentProofStatus" NOT NULL DEFAULT 'PENDING_REVIEW',
  "uploadedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "reviewedAt" TIMESTAMP(3),
  "reviewedBy" TEXT,
  "rejectReason" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "OrderPaymentProof_pkey" PRIMARY KEY ("id")
);

INSERT INTO "OrderPaymentProof" (
  "id", "orderId", "version", "url", "status", "uploadedAt", "createdAt", "updatedAt"
)
SELECT
  CONCAT('legacy_', "id"), "id", 1, "paymentProofUrl", 'PENDING_REVIEW',
  COALESCE("paymentProofUploadedAt", "createdAt"), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM "Order"
WHERE "paymentProofUrl" IS NOT NULL;

CREATE UNIQUE INDEX "OrderPaymentProof_orderId_version_key"
  ON "OrderPaymentProof"("orderId", "version");
CREATE INDEX "OrderPaymentProof_orderId_uploadedAt_idx"
  ON "OrderPaymentProof"("orderId", "uploadedAt");
CREATE INDEX "OrderPaymentProof_status_uploadedAt_idx"
  ON "OrderPaymentProof"("status", "uploadedAt");
ALTER TABLE "OrderPaymentProof"
  ADD CONSTRAINT "OrderPaymentProof_orderId_fkey"
  FOREIGN KEY ("orderId") REFERENCES "Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "ChatOutboxEvent" (
  "id" TEXT NOT NULL,
  "eventKey" TEXT NOT NULL,
  "type" TEXT NOT NULL,
  "aggregateId" TEXT NOT NULL,
  "payload" JSONB NOT NULL,
  "generation" INTEGER NOT NULL DEFAULT 1,
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "availableAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "lockedAt" TIMESTAMP(3),
  "processedAt" TIMESTAMP(3),
  "lastError" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ChatOutboxEvent_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ChatOutboxEvent_eventKey_key" ON "ChatOutboxEvent"("eventKey");
CREATE INDEX "ChatOutboxEvent_status_availableAt_idx" ON "ChatOutboxEvent"("status", "availableAt");
CREATE INDEX "ChatOutboxEvent_aggregateId_createdAt_idx" ON "ChatOutboxEvent"("aggregateId", "createdAt");
