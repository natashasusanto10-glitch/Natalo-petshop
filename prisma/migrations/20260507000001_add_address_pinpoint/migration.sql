-- Add pinpoint fields back to Address table
ALTER TABLE "Address" ADD COLUMN IF NOT EXISTS "latitude" DOUBLE PRECISION;
ALTER TABLE "Address" ADD COLUMN IF NOT EXISTS "longitude" DOUBLE PRECISION;
ALTER TABLE "Address" ADD COLUMN IF NOT EXISTS "pinpointAddress" TEXT;
ALTER TABLE "Address" ADD COLUMN IF NOT EXISTS "streetName" TEXT;
