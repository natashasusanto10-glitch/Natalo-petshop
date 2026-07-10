-- Menambahkan kolom video produk yang ada di prisma/schema.prisma (fitur
-- product-video / PR #71) tapi TIDAK PERNAH dimigrasikan ke tabel "Product".
--
-- Akibatnya: prisma.product.count() jalan (hanya select PK), tapi findMany()
-- men-select SEMUA kolom scalar Product termasuk video* -> Postgres throw
-- "column does not exist" -> getProducts() (lib/products.ts:835) nangkap error
-- di try/catch dan mengembalikan [] -> /api/products balik { total, items: [] }
-- -> storefront/app menampilkan NOL produk.
--
-- Kolom video ini semula masuk lewat `prisma db push` di DB lain/lama, jadi
-- sebagian environment sudah punya kolomnya dan sebagian belum. Migration ini
-- dibuat IDEMPOTEN (ADD COLUMN IF NOT EXISTS + CREATE UNIQUE INDEX IF NOT EXISTS)
-- supaya `prisma migrate deploy` aman di kedua kondisi tanpa gagal.
--
-- Mapping tipe Prisma (schema.prisma L378-382):
--   videoUrl          String?          -> TEXT (nullable)
--   videoGuid         String? @unique  -> TEXT (nullable) + unique index
--   videoStatus       String?          -> TEXT (nullable)
--   videoThumbnailUrl String?          -> TEXT (nullable)
--   videoDurationSec  Int?             -> INTEGER (nullable)
-- Hanya videoGuid yang @unique (slug & sku juga @unique tapi sudah ada di DB).
-- Semua nullable -> tanpa DEFAULT/backfill; NULL di-exclude dari unique index.

ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "videoUrl" TEXT;
ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "videoGuid" TEXT;
ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "videoStatus" TEXT;
ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "videoThumbnailUrl" TEXT;
ALTER TABLE "Product" ADD COLUMN IF NOT EXISTS "videoDurationSec" INTEGER;

CREATE UNIQUE INDEX IF NOT EXISTS "Product_videoGuid_key" ON "Product"("videoGuid");
