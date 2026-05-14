-- Postgres full-text + fuzzy search untuk Product.
-- pg_trgm: similarity / typo tolerance via trigram (gin_trgm_ops index)
-- unaccent: normalisasi diacritics (jarang dipakai bahasa Indonesia, tapi safe)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Kolom denormalized: gabungan name + brand + variant names + sku codes.
-- Diisi via app code (lib/search.ts syncProduct) saat produk berubah,
-- dan via script backfill untuk produk lama.
ALTER TABLE "Product"
  ADD COLUMN IF NOT EXISTS "searchText" TEXT NOT NULL DEFAULT '';

-- GIN trigram index: ILIKE '%x%' dan operator % (similarity) jadi index-scan.
-- Tanpa index ini, query similarity full-scan dan lambat di catalog besar.
CREATE INDEX IF NOT EXISTS "product_search_text_trgm_idx"
  ON "Product" USING gin ("searchText" gin_trgm_ops);

-- Index tambahan di name untuk prefix/exact match prioritas tinggi.
CREATE INDEX IF NOT EXISTS "product_name_trgm_idx"
  ON "Product" USING gin ("name" gin_trgm_ops);

-- Backfill awal untuk produk yang sudah ada. Sengaja sederhana (tanpa
-- variant/sku karena join multi-table di migration repetitif) — app code
-- akan refine via syncProduct + ada script reindex untuk re-populate
-- dengan full join.
UPDATE "Product" p
SET "searchText" = lower(
  coalesce(p.name, '') || ' ' ||
  coalesce((SELECT b.name FROM "Brand" b WHERE b.id = p."brandId"), '') || ' ' ||
  coalesce((SELECT c.name FROM "Category" c WHERE c.id = p."categoryId"), '')
);
