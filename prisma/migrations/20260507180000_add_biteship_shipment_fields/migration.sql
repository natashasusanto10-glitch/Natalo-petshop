ALTER TABLE "Order"
ADD COLUMN "shippingLatitude" DOUBLE PRECISION,
ADD COLUMN "shippingLongitude" DOUBLE PRECISION,
ADD COLUMN "shippingPinpointAddress" TEXT,
ADD COLUMN "biteshipOrderId" TEXT,
ADD COLUMN "biteshipTrackingUrl" TEXT,
ADD COLUMN "shipmentStatus" TEXT,
ADD COLUMN "biteshipRequest" JSONB,
ADD COLUMN "biteshipResponse" JSONB,
ADD COLUMN "biteshipError" TEXT;

CREATE INDEX "Order_biteshipOrderId_idx" ON "Order"("biteshipOrderId");
CREATE INDEX "Order_shipmentStatus_idx" ON "Order"("shipmentStatus");
