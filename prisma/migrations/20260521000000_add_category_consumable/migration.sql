-- Consumable detection — tambah kolom di Category untuk identifikasi
-- kategori habis pakai (mis. makanan, pasir, vitamin) vs durable
-- (mis. kandang, mainan, aksesoris).
--
-- Dipakai oleh recommendation engine (lib/purchase-affinity.ts):
--  - is_consumable=true → produk yang dibeli BOLEH muncul lagi di
--    rekomendasi (user butuh refill). Boost score saat sudah waktunya
--    refill.
--  - is_consumable=false (default) → produk yang dibeli di-exclude
--    (assumption durable, user sudah punya).
--  - typical_refill_days → estimasi siklus refill dalam hari (mis.
--    makanan 30, pasir 25, snack 14, vitamin 30). Null untuk durable.
--
-- Seed data ada di scripts/seed-consumable-categories.ts — jalankan
-- terpisah setelah migration apply.

ALTER TABLE "Category"
  ADD COLUMN "is_consumable" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "typical_refill_days" INTEGER;
