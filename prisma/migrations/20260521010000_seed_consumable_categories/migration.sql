-- Seed consumable categories — auto-apply via `prisma migrate deploy`
-- supaya tidak perlu manual run scripts/seed-consumable-categories.ts
-- di production.
--
-- Idempotent: pakai UPDATE WHERE slug IN (...). Aman re-run, hanya
-- update kategori yang slug-nya match.
--
-- Kategori yang ditambah admin di future tetap default isConsumable=false
-- (durable). Untuk flag kategori baru, run scripts/seed-consumable-categories.ts
-- atau edit langsung di Prisma Studio.

-- Pet food (siklus 30 hari)
UPDATE "Category" SET "is_consumable" = true, "typical_refill_days" = 30
WHERE "slug" IN (
  'makanan-kucing',
  'makanan-anjing',
  'makanan-burung',
  'makanan-ikan',
  'makanan-hamster',
  'makanan-reptil',
  'pet-food',
  'wet-food',
  'dry-food'
);

-- Pasir kucing (siklus 25 hari)
UPDATE "Category" SET "is_consumable" = true, "typical_refill_days" = 25
WHERE "slug" IN (
  'pasir-kucing',
  'cat-litter',
  'litter'
);

-- Snack & treats (siklus 14 hari)
UPDATE "Category" SET "is_consumable" = true, "typical_refill_days" = 14
WHERE "slug" IN (
  'snack',
  'snack-kucing',
  'snack-anjing',
  'treats',
  'biskuit'
);

-- Vitamin & suplemen (siklus 30 hari)
UPDATE "Category" SET "is_consumable" = true, "typical_refill_days" = 30
WHERE "slug" IN (
  'vitamin',
  'suplemen',
  'vitamin-suplemen'
);

-- Obat cacing (siklus 90 hari, dosis 3 bulan)
UPDATE "Category" SET "is_consumable" = true, "typical_refill_days" = 90
WHERE "slug" IN (
  'obat-cacing'
);

-- Susu / formula (siklus 21 hari, anak hewan)
UPDATE "Category" SET "is_consumable" = true, "typical_refill_days" = 21
WHERE "slug" IN (
  'susu',
  'milk-formula'
);

-- Shampoo & grooming (siklus 60 hari)
UPDATE "Category" SET "is_consumable" = true, "typical_refill_days" = 60
WHERE "slug" IN (
  'sampo',
  'shampoo',
  'grooming-spray'
);

-- Pads / popok (siklus 21 hari)
UPDATE "Category" SET "is_consumable" = true, "typical_refill_days" = 21
WHERE "slug" IN (
  'popok',
  'training-pad',
  'pee-pad'
);
