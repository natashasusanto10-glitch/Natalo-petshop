-- Store Biteship area references for saved customer addresses and order snapshots.
-- Area IDs are the primary identifier for regular courier rates/orders.

ALTER TABLE "Address" ADD COLUMN IF NOT EXISTS "areaId" VARCHAR(100);
ALTER TABLE "Address" ADD COLUMN IF NOT EXISTS "areaLabel" TEXT;
ALTER TABLE "Address" ADD COLUMN IF NOT EXISTS "provinceName" VARCHAR(100);
ALTER TABLE "Address" ADD COLUMN IF NOT EXISTS "cityName" VARCHAR(100);
ALTER TABLE "Address" ADD COLUMN IF NOT EXISTS "districtName" VARCHAR(100);

ALTER TABLE "Order" ADD COLUMN IF NOT EXISTS "shippingAreaId" VARCHAR(100);
ALTER TABLE "Order" ADD COLUMN IF NOT EXISTS "shippingAreaLabel" TEXT;
ALTER TABLE "Order" ADD COLUMN IF NOT EXISTS "shippingProvinceName" VARCHAR(100);
ALTER TABLE "Order" ADD COLUMN IF NOT EXISTS "shippingDistrictName" VARCHAR(100);

CREATE INDEX IF NOT EXISTS "Address_areaId_idx" ON "Address"("areaId");
CREATE INDEX IF NOT EXISTS "Order_shippingAreaId_idx" ON "Order"("shippingAreaId");
