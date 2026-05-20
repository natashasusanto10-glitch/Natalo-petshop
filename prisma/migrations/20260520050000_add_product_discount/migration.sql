-- Promo Toko ala Shopee Seller — diskon harga coret per-produk dengan
-- periode terjadwal. Berbeda dari Flash Sale (urgent, jam-jaman) dan
-- Voucher (kode kupon checkout).

CREATE TYPE "DiscountType" AS ENUM ('PERCENTAGE', 'FIXED_AMOUNT');

CREATE TABLE "ProductDiscount" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "discountType" "DiscountType" NOT NULL,
  "discountValue" INTEGER NOT NULL,
  "maxDiscountCap" INTEGER,
  "startsAt" TIMESTAMP(3) NOT NULL,
  "endsAt" TIMESTAMP(3) NOT NULL,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "productIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "ProductDiscount_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "ProductDiscount_startsAt_endsAt_idx"
  ON "ProductDiscount"("startsAt", "endsAt");
CREATE INDEX "ProductDiscount_isActive_idx"
  ON "ProductDiscount"("isActive");
