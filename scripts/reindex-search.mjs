/**
 * Setup search index + full reindex semua produk.
 *
 * Cara pakai:
 *   1. Pastikan Meilisearch jalan: docker compose up -d
 *   2. Run:  node scripts/reindex-search.mjs
 *
 * Aman dijalankan kapan saja & berkali-kali (idempotent).
 *
 * Mode flag:
 *   --setup-only     hanya update index settings (tidak re-index data)
 *   --skip-setup     skip setup, langsung re-index data
 */

import { createRequire } from "module";
import { config } from "dotenv";

config(); // load .env

const require = createRequire(import.meta.url);
const { PrismaClient } = require("@prisma/client");
const { Meilisearch } = require("meilisearch");

const prisma = new PrismaClient();

const HOST = process.env.MEILISEARCH_HOST ?? "http://localhost:7700";
const KEY = process.env.MEILISEARCH_API_KEY ?? "";
const INDEX_NAME = process.env.MEILISEARCH_INDEX ?? "products";

const SETUP_ONLY = process.argv.includes("--setup-only");
const SKIP_SETUP = process.argv.includes("--skip-setup");

const meili = new Meilisearch({ host: HOST, apiKey: KEY });

const SYNONYMS = {
  anjing: ["dog"],
  dog: ["anjing"],
  kucing: ["cat"],
  cat: ["kucing"],
  ikan: ["fish"],
  fish: ["ikan"],
  pakan: ["makanan", "food"],
  makanan: ["pakan", "food"],
  food: ["makanan", "pakan"],
  vitamin: ["suplemen"],
  suplemen: ["vitamin"],
  "obat kutu": ["fleatick", "anti kutu"],
  fleatick: ["obat kutu", "anti kutu"],
  "anti kutu": ["obat kutu", "fleatick"],
};

async function setupIndex() {
  console.log(`📡 Meilisearch host: ${HOST}`);
  console.log(`📦 Index: ${INDEX_NAME}\n`);

  // Health check
  try {
    await meili.health();
  } catch (e) {
    console.error("❌ Meilisearch tidak bisa diakses!");
    console.error(`   Pastikan docker container berjalan: docker compose up -d`);
    console.error(`   Error: ${e.message}\n`);
    process.exit(1);
  }
  console.log("✅ Meilisearch healthy\n");

  // Pastikan index ada
  try {
    await meili.getIndex(INDEX_NAME);
    console.log(`ℹ️  Index "${INDEX_NAME}" sudah ada`);
  } catch {
    await meili.createIndex(INDEX_NAME, { primaryKey: "id" });
    console.log(`✨ Index "${INDEX_NAME}" baru dibuat`);
  }

  const idx = meili.index(INDEX_NAME);

  console.log("⚙️  Update searchable attributes...");
  await idx.updateSearchableAttributes([
    "name",
    "brand_name",
    "category_name",
    "variant_names",
    "sku_codes",
    "description",
  ]);

  console.log("⚙️  Update filterable attributes...");
  await idx.updateFilterableAttributes([
    "category_id", "category_slug",
    "brand_id", "brand_slug",
    "price_min", "price_max",
    "total_stock", "weight_grams",
    "avg_rating", "review_count",
    "is_active",
  ]);

  console.log("⚙️  Update sortable attributes...");
  await idx.updateSortableAttributes([
    "price_min", "created_at", "avg_rating", "review_count",
  ]);

  console.log("⚙️  Update synonyms...");
  await idx.updateSynonyms(SYNONYMS);

  console.log("⚙️  Update typo tolerance...");
  await idx.updateTypoTolerance({
    enabled: true,
    minWordSizeForTypos: { oneTypo: 4, twoTypos: 8 },
  });

  console.log("✅ Settings updated\n");
}

function buildDoc(p) {
  // Cek varian aktif
  const activeVariants = p.variants.filter((v) => !v.deletedAt && v.isActive);

  let priceMin = p.price;
  let priceMax = p.price;
  let totalStock = p.stock;

  if (p.hasVariants && activeVariants.length > 0) {
    const prices = activeVariants.map((v) => v.price);
    priceMin = Math.min(...prices);
    priceMax = Math.max(...prices);
    totalStock = activeVariants.reduce((s, v) => s + v.stock, 0);
  }

  // Variant names (deduplicated)
  const variantNames = [
    ...new Set(
      activeVariants
        .flatMap((v) => v.options.map((vo) => vo.option?.value))
        .filter(Boolean)
    ),
  ];

  const skuCodes = activeVariants
    .map((v) => v.sku)
    .filter(Boolean);

  return {
    id: p.id,
    slug: p.slug,
    name: p.name,
    description: p.description ?? "",
    category_id: p.categoryId,
    category_slug: p.category?.slug ?? null,
    category_name: p.category?.name ?? null,
    brand_id: p.brandId,
    brand_slug: p.brand?.slug ?? null,
    brand_name: p.brand?.name ?? null,
    variant_names: variantNames,
    sku_codes: skuCodes,
    price_min: priceMin,
    price_max: priceMax,
    total_stock: totalStock,
    weight_grams: p.weightGram,
    avg_rating: p.avgRating,
    review_count: p.reviewCount,
    created_at: Math.floor(p.createdAt.getTime() / 1000),
    image_url: p.imageUrl,
    is_active: p.isActive,
  };
}

async function reindexAll() {
  console.log("📥 Fetching products dari database...");
  const products = await prisma.product.findMany({
    include: {
      category: { select: { id: true, name: true, slug: true } },
      brand: { select: { id: true, name: true, slug: true } },
      variants: {
        include: {
          options: { include: { option: { select: { value: true } } } },
        },
      },
    },
  });
  console.log(`   ${products.length} produk dimuat\n`);

  console.log("🔨 Build dokumen index...");
  const docs = products.map(buildDoc);

  console.log(`📤 Upload ke Meilisearch (batch 1000)...`);
  const idx = meili.index(INDEX_NAME);

  // Clear existing first
  await idx.deleteAllDocuments();

  const BATCH = 1000;
  let uploaded = 0;
  for (let i = 0; i < docs.length; i += BATCH) {
    const chunk = docs.slice(i, i + BATCH);
    await idx.addDocuments(chunk);
    uploaded += chunk.length;
    console.log(`   [${uploaded}/${docs.length}]`);
  }

  console.log(`\n✅ Re-index selesai: ${docs.length} produk\n`);

  // Wait for indexing to complete (background job di Meilisearch)
  console.log("⏳ Menunggu indexing selesai...");
  let stats = await idx.getStats();
  let waited = 0;
  while (stats.isIndexing && waited < 60) {
    await new Promise((r) => setTimeout(r, 1000));
    stats = await idx.getStats();
    waited++;
  }

  const final = await idx.getStats();
  console.log(`📊 Index stats:`);
  console.log(`   Total documents : ${final.numberOfDocuments}`);
  console.log(`   Is indexing     : ${final.isIndexing}`);
}

async function main() {
  console.log("=".repeat(60));
  console.log("  Reindex Search — Meilisearch");
  console.log("=".repeat(60) + "\n");

  if (!SKIP_SETUP) await setupIndex();
  if (!SETUP_ONLY) await reindexAll();

  console.log("\n🎉 Done!");
}

main()
  .catch((e) => {
    console.error("❌ Error:", e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
