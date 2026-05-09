-- Secure guest tracking links for order detail pages.
ALTER TABLE "Order" ADD COLUMN "trackingToken" TEXT;

CREATE UNIQUE INDEX "Order_trackingToken_key" ON "Order"("trackingToken");
