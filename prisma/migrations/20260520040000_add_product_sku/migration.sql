-- Add SKU Induk (parent product SKU) — single product master identifier.
-- Berbeda namespace dari ProductVariant.sku (variant SKU per kombinasi).
-- Nullable supaya existing produk tidak perlu diisi paksa; admin bisa
-- isi belakangan kalau perlu.
ALTER TABLE "Product" ADD COLUMN "sku" TEXT;

-- Unique constraint scoped ke Product saja. NULL value tidak counted ke
-- unique constraint di PostgreSQL — produk tanpa SKU tetap valid.
CREATE UNIQUE INDEX "Product_sku_key" ON "Product"("sku");
