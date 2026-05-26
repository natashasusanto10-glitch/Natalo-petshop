-- shippingDriverInfo untuk kurir INSTANT yang tidak punya resi.
-- Admin isi: "Driver: Pak Budi | HP: 0812... | Plat: B 1234 ABC"

-- AlterTable
ALTER TABLE "Order" ADD COLUMN "shippingDriverInfo" TEXT;
