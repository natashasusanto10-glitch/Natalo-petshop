/**
 * Sync nama + deskripsi produk dari prisma/products_import.json ke
 * production DB. HANYA update field name + description — tidak menyentuh
 * price, stock, weightGram, imageUrl, categoryId, brandId, isActive,
 * hasVariants, dll.
 *
 * Aman untuk dijalankan setelah admin edit manual (mis. ubah harga, stok,
 * foto) — edit tersebut tidak akan ke-revert.
 *
 * Match by slug. Produk di JSON yang slug-nya tidak ada di DB akan
 * di-skip (tidak create produk baru). Kebalikan dari prisma/seed.ts yg
 * upsert (create + update everything).
 *
 * Cara pakai:
 *   npx dotenv -e .env -- tsx scripts/sync-product-text.ts        # production
 *   npx dotenv -e .env.local -- tsx scripts/sync-product-text.ts  # local
 *
 * Atau via npm:
 *   npm run db:sync-product-text:prod
 */

import path from "path";
import fs from "fs";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

interface ProductData {
  name: string;
  slug: string;
  description?: string;
  brand?: string;
  category?: string;
  weightGram?: number;
  // Field lain ada di JSON tapi tidak di-pakai script ini.
}

interface ImportData {
  products: ProductData[];
}

/**
 * Fallback description generator — match logic di prisma/seed.ts agar
 * konsisten kalau description di JSON kosong.
 */
function generateDescription(prod: ProductData): string {
  const brand = prod.brand ?? "Natalo";
  const weight = prod.weightGram ? `${prod.weightGram} gram` : "info di label";
  return `${prod.name} dari ${brand}. Berat produk: ${weight}.`;
}

async function main() {
  const dataPath = path.join(__dirname, "..", "prisma", "products_import.json");
  if (!fs.existsSync(dataPath)) {
    console.error(`❌ products_import.json tidak ditemukan di ${dataPath}`);
    process.exit(1);
  }

  const raw = fs.readFileSync(dataPath, "utf-8");
  const data = JSON.parse(raw) as ImportData;
  if (!Array.isArray(data.products)) {
    console.error("❌ products_import.json tidak punya field 'products' (array).");
    process.exit(1);
  }

  const dbUrl = process.env.DATABASE_URL ?? "";
  const host =
    dbUrl.replace(/^postgres(?:ql)?:\/\/[^@]+@/, "").split("/")[0] ?? "(unknown)";
  console.log(`\n🎯 TARGET DB host: ${host}`);
  console.log(`📦 Total produk di JSON: ${data.products.length}`);
  console.log(`✏️  Update HANYA field: name, description\n`);
  console.log("Mulai sync dalam 3 detik. Ctrl+C untuk batal.\n");
  await new Promise((r) => setTimeout(r, 3000));

  let updated = 0;
  let skipped = 0;
  let unchanged = 0;
  let errored = 0;
  const startedAt = Date.now();

  for (let i = 0; i < data.products.length; i++) {
    const prod = data.products[i];
    if (!prod.slug || !prod.name) {
      skipped++;
      continue;
    }

    const description = prod.description?.trim() || generateDescription(prod);

    try {
      // Cek dulu apakah produk ada — supaya kita bisa hitung "unchanged"
      // (slug tidak ada di DB) terpisah dari benar-benar updated.
      const existing = await prisma.product.findUnique({
        where: { slug: prod.slug },
        select: { id: true, name: true, description: true },
      });

      if (!existing) {
        skipped++;
        continue;
      }

      // Skip kalau text sudah identik — hindari unnecessary write.
      if (existing.name === prod.name && existing.description === description) {
        unchanged++;
        continue;
      }

      await prisma.product.update({
        where: { id: existing.id },
        data: { name: prod.name, description },
      });
      updated++;
    } catch (err) {
      errored++;
      console.error(
        `⚠️  Error update slug=${prod.slug}:`,
        err instanceof Error ? err.message : err,
      );
    }

    if ((i + 1) % 200 === 0) {
      console.log(
        `   ... ${i + 1}/${data.products.length} (updated=${updated}, unchanged=${unchanged}, skipped=${skipped}, error=${errored})`,
      );
    }
  }

  const elapsed = Math.round((Date.now() - startedAt) / 1000);
  console.log(`\n✅ Sync selesai dalam ${elapsed}s`);
  console.log(`   📝 Updated   : ${updated}`);
  console.log(`   ⚪ Unchanged : ${unchanged} (text sudah sama, di-skip)`);
  console.log(`   ➖ Skipped   : ${skipped} (slug tidak ada di DB / data invalid)`);
  if (errored > 0) {
    console.log(`   ⚠️  Error    : ${errored}`);
  }
}

main()
  .catch((err) => {
    console.error("\n❌ Fatal:", err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
