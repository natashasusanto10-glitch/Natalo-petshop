-- Refactor ProductDiscount → 2 model terpisah:
-- 1. ProductDiscount (metadata: name, periode, isActive)
-- 2. ProductDiscountItem (per-product/variant: discountedPrice, isItemActive)
--
-- Pattern Shopee Seller "Buat Promo Toko" — tiap produk dalam satu
-- promo bisa punya harga diskon BERBEDA + toggle aktif independent.
-- Untuk produk berVarian: 1 row per varian.
--
-- Data dummy, drop + recreate (Pilihan A).

-- Drop existing
DROP TABLE IF EXISTS "ProductDiscount";
DROP TYPE IF EXISTS "DiscountType";

-- Recreate ProductDiscount (metadata only)
CREATE TABLE "ProductDiscount" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "startsAt" TIMESTAMP(3) NOT NULL,
  "endsAt" TIMESTAMP(3) NOT NULL,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "ProductDiscount_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "ProductDiscount_startsAt_endsAt_idx"
  ON "ProductDiscount"("startsAt", "endsAt");
CREATE INDEX "ProductDiscount_isActive_idx"
  ON "ProductDiscount"("isActive");

-- Create ProductDiscountItem (per-product/variant config)
CREATE TABLE "ProductDiscountItem" (
  "id" TEXT NOT NULL,
  "discountId" TEXT NOT NULL,
  "productId" TEXT NOT NULL,
  "variantId" TEXT,
  "discountedPrice" INTEGER NOT NULL,
  "isItemActive" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "ProductDiscountItem_pkey" PRIMARY KEY ("id")
);

-- Foreign keys dengan cascade delete:
-- - Hapus ProductDiscount → semua item ikut terhapus
-- - Hapus Product / ProductVariant → item terkait juga terhapus
ALTER TABLE "ProductDiscountItem"
  ADD CONSTRAINT "ProductDiscountItem_discountId_fkey"
  FOREIGN KEY ("discountId") REFERENCES "ProductDiscount"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ProductDiscountItem"
  ADD CONSTRAINT "ProductDiscountItem_productId_fkey"
  FOREIGN KEY ("productId") REFERENCES "Product"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ProductDiscountItem"
  ADD CONSTRAINT "ProductDiscountItem_variantId_fkey"
  FOREIGN KEY ("variantId") REFERENCES "ProductVariant"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

-- Unique constraint: 1 produk-variant kombinasi unik per discount.
-- Karena NULL di PG dianggap unique (multiple NULL allowed di unique),
-- pakai partial index dengan COALESCE supaya NULL variantId tetap unik.
CREATE UNIQUE INDEX "ProductDiscountItem_discountId_productId_variantId_key"
  ON "ProductDiscountItem"("discountId", "productId", COALESCE("variantId", ''));

-- Index untuk query "active discount untuk produk X / varian Y"
-- (dipakai Phase 1D customer-side price calculator).
CREATE INDEX "ProductDiscountItem_productId_variantId_idx"
  ON "ProductDiscountItem"("productId", "variantId");
