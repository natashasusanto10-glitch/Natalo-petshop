/**
 * Import 2.222 produk dari products.json ke database.
 *
 * Cara pakai:
 *   node scripts/import-products.mjs
 *
 * Opsi:
 *   node scripts/import-products.mjs --dry-run   (simulasi tanpa nulis ke DB)
 *   node scripts/import-products.mjs --reset      (hapus semua produk & kategori dulu, lalu import ulang)
 *
 * Catatan:
 *   - Gambar pakai Shopee CDN URL (sementara). Setelah foto di-download & upload ke server,
 *     jalankan scripts/update-image-urls.mjs untuk ganti ke URL lokal.
 *   - Price, stock, weight default ke 0/500 — lengkapi via admin panel setelah import.
 *   - Slug duplikat otomatis di-suffix dengan -2, -3, dst.
 */

import { createRequire } from "module";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import path from "path";

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Prisma Client dari node_modules project
const { PrismaClient } = require("@prisma/client");
const prisma = new PrismaClient();

const PRODUCTS_JSON = path.resolve(__dirname, "../../../Downloads/products.json");
const BATCH_SIZE = 50;
const DRY_RUN = process.argv.includes("--dry-run");
const RESET = process.argv.includes("--reset");

// ── Mapping kategori → slug ───────────────────────────────────────
const CATEGORY_MAP = {
  "Aksesoris":      "aksesoris",
  "Anjing":         "anjing",
  "Burung":         "burung",
  "Grooming":       "grooming",
  "Ikan":           "ikan",
  "Kelinci":        "kelinci",
  "Kucing":         "kucing",
  "Lainnya":        "lainnya",
  "Obat & Vitamin": "obat-vitamin",
  "Pasir & Toilet": "pasir-toilet",
  "Reptil":         "reptil",
};

// ── Helpers ──────────────────────────────────────────────────────
function slugify(str) {
  return str
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .trim()
    .replace(/[\s_]+/g, "-")
    .replace(/-+/g, "-")
    .slice(0, 100);
}

function log(msg) { console.log(msg); }
function warn(msg) { console.warn("⚠️  " + msg); }

// ── Main ──────────────────────────────────────────────────────────
async function main() {
  log("=".repeat(60));
  log("  Import Produk Natalo Petshop");
  log("=".repeat(60));
  if (DRY_RUN) log("🔍 DRY RUN — tidak ada yang ditulis ke database\n");

  // 1. Baca JSON
  let rawProducts;
  try {
    rawProducts = JSON.parse(readFileSync(PRODUCTS_JSON, "utf8"));
  } catch (e) {
    console.error(`ERROR: Tidak bisa baca ${PRODUCTS_JSON}`);
    console.error("Pastikan path benar. Ubah konstanta PRODUCTS_JSON di atas script ini.");
    process.exit(1);
  }
  log(`📦 Membaca ${rawProducts.length} produk dari JSON...\n`);

  // 2. Reset jika diminta
  if (RESET && !DRY_RUN) {
    log("🗑️  --reset: menghapus semua produk & kategori...");
    await prisma.orderItem.deleteMany({});
    await prisma.favorite.deleteMany({});
    await prisma.product.deleteMany({});
    await prisma.category.deleteMany({});
    log("   Selesai dihapus.\n");
  }

  // 3. Upsert semua kategori
  const categoryNames = [...new Set(rawProducts.map(p => p.category).filter(Boolean))];
  const categoryIdMap = {}; // name → id

  log(`🏷️  Membuat ${categoryNames.length} kategori...`);
  for (const name of categoryNames) {
    const slug = CATEGORY_MAP[name] ?? slugify(name);
    if (!DRY_RUN) {
      const cat = await prisma.category.upsert({
        where: { slug },
        create: { name, slug },
        update: { name },
      });
      categoryIdMap[name] = cat.id;
    } else {
      categoryIdMap[name] = `dry-${slug}`;
    }
    log(`   ${name} → ${slug}`);
  }
  log("");

  // 4. Deduplikasi slug
  const slugCount = {};
  const processedProducts = rawProducts.map(p => {
    let slug = p.slug || slugify(p.name);
    if (!slug) slug = `produk-${p.id}`;

    slugCount[slug] = (slugCount[slug] || 0) + 1;
    if (slugCount[slug] > 1) {
      slug = `${slug}-${slugCount[slug]}`;
    }
    return { ...p, _slug: slug };
  });

  const dupCount = rawProducts.length - new Set(processedProducts.map(p => p._slug)).size;
  if (dupCount > 0) warn(`${dupCount} slug duplikat otomatis diberi suffix (-2, -3, dst)\n`);

  // 5. Import produk dalam batch
  log(`🚀 Mengimport ${processedProducts.length} produk (batch ${BATCH_SIZE})...`);
  let ok = 0, skip = 0, fail = 0;
  const errors = [];

  for (let i = 0; i < processedProducts.length; i += BATCH_SIZE) {
    const batch = processedProducts.slice(i, i + BATCH_SIZE);

    if (!DRY_RUN) {
      for (const p of batch) {
        try {
          // Ambil gambar utama
          const primaryImg = p.images?.find(img => img.is_primary) ?? p.images?.[0] ?? null;
          const imageUrl = primaryImg ? primaryImg.source_url : null;

          await prisma.product.upsert({
            where: { slug: p._slug },
            create: {
              name: p.name,
              slug: p._slug,
              description: p.description || "",
              price: p.price ?? 0,
              stock: p.stock ?? 0,
              weightGram: p.weight_grams ?? 500,
              imageUrl: imageUrl,
              isActive: false,           // nonaktif dulu sampai harga diisi
              categoryId: p.category ? categoryIdMap[p.category] : null,
            },
            update: {
              name: p.name,
              description: p.description || "",
              imageUrl: imageUrl,
              categoryId: p.category ? categoryIdMap[p.category] : null,
            },
          });
          ok++;
        } catch (e) {
          fail++;
          errors.push(`#${p.id} ${p.name.slice(0, 40)}: ${e.message}`);
        }
      }
    } else {
      ok += batch.length;
    }

    const done = Math.min(i + BATCH_SIZE, processedProducts.length);
    process.stdout.write(`\r   [${done}/${processedProducts.length}] OK:${ok} Gagal:${fail}  `);
  }

  log("\n");

  // 6. Ringkasan
  log("=".repeat(60));
  log(`✅ Berhasil : ${ok}`);
  if (skip > 0) log(`⏭️  Di-skip  : ${skip}`);
  if (fail > 0) {
    log(`❌ Gagal    : ${fail}`);
    log("\nDetail error:");
    errors.slice(0, 20).forEach(e => log("   " + e));
    if (errors.length > 20) log(`   ... dan ${errors.length - 20} lainnya`);
  }
  log("=".repeat(60));

  if (!DRY_RUN && ok > 0) {
    log("\n📋 Langkah selanjutnya:");
    log("   1. Buka /admin/products untuk set harga & aktifkan produk");
    log("   2. Produk di-import dengan isActive=false (tersembunyi dari publik)");
    log("   3. Download foto: python download_images.py  (di folder Downloads)");
    log("   4. Setelah foto di-upload ke server, jalankan update-image-urls.mjs");
  }
}

main()
  .catch(e => { console.error(e); process.exit(1); })
  .finally(() => prisma.$disconnect());
