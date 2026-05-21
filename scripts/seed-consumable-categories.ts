/**
 * Seed isConsumable + typicalRefillDays untuk kategori utama pet shop.
 *
 * Jalankan setelah migration `add_category_consumable` apply:
 *   npx tsx scripts/seed-consumable-categories.ts
 *
 * Idempotent — bisa di-run berkali-kali, cuma update yang flag-nya
 * belum match. Tidak touch kategori yang slug-nya tidak ada di list.
 *
 * Kategori yang admin tambah baru di future tetap default isConsumable=false
 * (durable). Untuk flag kategori baru, edit list ini + rerun, atau
 * pakai Prisma Studio manual.
 */
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

interface ConsumableSeed {
  slug: string;
  refillDays: number;
  // Display name untuk log saja
  displayHint: string;
}

const CONSUMABLE_CATEGORIES: ConsumableSeed[] = [
  // ─── Pet food (siklus 30 hari rata-rata) ───
  { slug: "makanan-kucing", refillDays: 30, displayHint: "Makanan Kucing" },
  { slug: "makanan-anjing", refillDays: 30, displayHint: "Makanan Anjing" },
  { slug: "makanan-burung", refillDays: 30, displayHint: "Makanan Burung" },
  { slug: "makanan-ikan", refillDays: 30, displayHint: "Makanan Ikan" },
  { slug: "makanan-hamster", refillDays: 30, displayHint: "Makanan Hamster" },
  { slug: "makanan-reptil", refillDays: 30, displayHint: "Makanan Reptil" },
  { slug: "pet-food", refillDays: 30, displayHint: "Pet Food (generic)" },
  { slug: "wet-food", refillDays: 30, displayHint: "Wet Food" },
  { slug: "dry-food", refillDays: 30, displayHint: "Dry Food" },

  // ─── Pasir kucing (siklus 25 hari) ───
  { slug: "pasir-kucing", refillDays: 25, displayHint: "Pasir Kucing" },
  { slug: "cat-litter", refillDays: 25, displayHint: "Cat Litter" },
  { slug: "litter", refillDays: 25, displayHint: "Litter" },

  // ─── Snack & treats (siklus 14 hari — habis lebih cepat) ───
  { slug: "snack", refillDays: 14, displayHint: "Snack" },
  { slug: "snack-kucing", refillDays: 14, displayHint: "Snack Kucing" },
  { slug: "snack-anjing", refillDays: 14, displayHint: "Snack Anjing" },
  { slug: "treats", refillDays: 14, displayHint: "Treats" },
  { slug: "biskuit", refillDays: 14, displayHint: "Biskuit" },

  // ─── Vitamin & suplemen (siklus 30 hari, 1 botol = 1 bulan dose) ───
  { slug: "vitamin", refillDays: 30, displayHint: "Vitamin" },
  { slug: "suplemen", refillDays: 30, displayHint: "Suplemen" },
  { slug: "vitamin-suplemen", refillDays: 30, displayHint: "Vitamin & Suplemen" },
  { slug: "obat-cacing", refillDays: 90, displayHint: "Obat Cacing (3 bulan)" },

  // ─── Susu / formula (siklus 21 hari, anak hewan tumbuh cepat) ───
  { slug: "susu", refillDays: 21, displayHint: "Susu" },
  { slug: "milk-formula", refillDays: 21, displayHint: "Milk Formula" },

  // ─── Shampoo & grooming (siklus 60 hari — 1 botol pakai ~2 bulan) ───
  { slug: "sampo", refillDays: 60, displayHint: "Sampo" },
  { slug: "shampoo", refillDays: 60, displayHint: "Shampoo" },
  { slug: "grooming-spray", refillDays: 60, displayHint: "Grooming Spray" },

  // ─── Pads / popok (siklus 21 hari, training pads habis cepat) ───
  { slug: "popok", refillDays: 21, displayHint: "Popok" },
  { slug: "training-pad", refillDays: 21, displayHint: "Training Pad" },
  { slug: "pee-pad", refillDays: 21, displayHint: "Pee Pad" },
];

async function main() {
  console.log("Seeding consumable categories...\n");

  let updated = 0;
  let skipped = 0;
  let notFound = 0;

  for (const seed of CONSUMABLE_CATEGORIES) {
    const existing = await prisma.category.findUnique({
      where: { slug: seed.slug },
    });

    if (!existing) {
      console.log(`  ⊘ ${seed.slug} (${seed.displayHint}) — kategori tidak ada, skip`);
      notFound += 1;
      continue;
    }

    // Skip kalau sudah match (idempotency)
    if (
      existing.isConsumable === true &&
      existing.typicalRefillDays === seed.refillDays
    ) {
      console.log(`  · ${seed.slug} — sudah ter-set (${seed.refillDays} hari)`);
      skipped += 1;
      continue;
    }

    await prisma.category.update({
      where: { slug: seed.slug },
      data: {
        isConsumable: true,
        typicalRefillDays: seed.refillDays,
      },
    });
    console.log(
      `  ✓ ${seed.slug} → isConsumable=true, refillDays=${seed.refillDays}`,
    );
    updated += 1;
  }

  console.log(`\nDone. Updated: ${updated}, Skipped: ${skipped}, Not found: ${notFound}`);
  console.log(`Not found OK — kategori belum ada di DB, akan diabaikan.`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
