-- AlterTable
ALTER TABLE "Address"
  ADD COLUMN IF NOT EXISTS "street_name" TEXT;
