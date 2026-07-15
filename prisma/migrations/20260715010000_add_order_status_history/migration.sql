CREATE TABLE "OrderStatusHistory" (
  "id" TEXT NOT NULL,
  "orderId" TEXT NOT NULL,
  "status" "OrderStatus" NOT NULL,
  "occurredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "actorType" TEXT NOT NULL DEFAULT 'SYSTEM',
  "actorId" TEXT,
  "metadata" JSONB,
  "idempotencyKey" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "OrderStatusHistory_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "OrderStatusHistory_idempotencyKey_key"
  ON "OrderStatusHistory"("idempotencyKey");
CREATE INDEX "OrderStatusHistory_orderId_occurredAt_idx"
  ON "OrderStatusHistory"("orderId", "occurredAt");
CREATE INDEX "OrderStatusHistory_status_occurredAt_idx"
  ON "OrderStatusHistory"("status", "occurredAt");

ALTER TABLE "OrderStatusHistory"
  ADD CONSTRAINT "OrderStatusHistory_orderId_fkey"
  FOREIGN KEY ("orderId") REFERENCES "Order"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
