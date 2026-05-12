/**
 * Setup search index + full reindex semua produk.
 *
 * Cara pakai:
 *   1. Pastikan Meilisearch jalan: docker compose up -d
 *   2. Run: node scripts/reindex-search.mjs
 *
 * Aman untuk live traffic: full reindex dibangun di temporary index,
 * diverifikasi, lalu di-swap atomik ke index utama. Index utama lama tetap
 * melayani traffic sampai swap berhasil.
 *
 * Mode flag:
 *   --setup-only     hanya update settings index utama
 *   --skip-setup     skip setup index utama sebelum reindex
 *   --dry-run        fetch DB + build dokumen tanpa menulis ke Meilisearch
 */

import { createRequire } from "module";
import { config } from "dotenv";
import {
  applyProductIndexSettings,
  productToSearchDoc,
} from "../lib/search-document.mjs";

config();

const require = createRequire(import.meta.url);
const { PrismaClient } = require("@prisma/client");
const { Meilisearch } = require("meilisearch");

const prisma = new PrismaClient();

const HOST = process.env.MEILISEARCH_HOST ?? "http://localhost:7700";
const KEY = process.env.MEILISEARCH_API_KEY ?? "";
const INDEX_NAME = process.env.MEILISEARCH_INDEX ?? "products";
const WAIT_OPTIONS = { timeout: 120_000, interval: 500 };

const SETUP_ONLY = process.argv.includes("--setup-only");
const SKIP_SETUP = process.argv.includes("--skip-setup");
const DRY_RUN = process.argv.includes("--dry-run");

const meili = new Meilisearch({ host: HOST, apiKey: KEY });

function assertTaskSucceeded(task, label) {
  if (task.status !== "succeeded") {
    throw new Error(`${label} failed: ${JSON.stringify(task.error ?? task)}`);
  }
  return task;
}

async function waitTask(taskPromise, label) {
  const task = typeof taskPromise.waitTask === "function"
    ? await taskPromise.waitTask(WAIT_OPTIONS)
    : await meili.tasks.waitForTask((await taskPromise).taskUid, WAIT_OPTIONS);
  return assertTaskSucceeded(task, label);
}

async function ensureIndex(uid) {
  try {
    await meili.getIndex(uid);
    return meili.index(uid);
  } catch {
    await waitTask(meili.createIndex(uid, { primaryKey: "id" }), `create index ${uid}`);
    return meili.index(uid);
  }
}

async function deleteIndexIfExists(uid) {
  try {
    await meili.getIndex(uid);
  } catch {
    return false;
  }
  await waitTask(meili.deleteIndex(uid), `delete index ${uid}`);
  return true;
}

async function setupIndex(uid = INDEX_NAME) {
  console.log(`Meilisearch host: ${HOST}`);
  console.log(`Index: ${uid}\n`);

  await meili.health();
  const idx = await ensureIndex(uid);

  console.log("Update index settings...");
  await applyProductIndexSettings(idx, { wait: true, waitOptions: WAIT_OPTIONS });
  console.log("Settings updated\n");

  return idx;
}

async function fetchProducts() {
  console.log("Fetching products dari database...");
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
  return products;
}

function buildDocs(products) {
  console.log("Build dokumen index...");
  const docs = products.map(productToSearchDoc);
  const requiredKeys = [
    "id",
    "slug",
    "name",
    "description",
    "category_id",
    "category_slug",
    "category_name",
    "brand_id",
    "brand_slug",
    "brand_name",
    "variant_names",
    "sku_codes",
    "price_min",
    "price_max",
    "discount_price",
    "stock",
    "total_stock",
    "weight_grams",
    "avg_rating",
    "review_count",
    "created_at",
    "image_url",
    "is_active",
    "has_variants",
  ];

  for (const doc of docs) {
    const missing = requiredKeys.filter((key) => !(key in doc));
    if (missing.length > 0) {
      throw new Error(`Dokumen ${doc.id ?? "(unknown)"} missing keys: ${missing.join(", ")}`);
    }
  }

  return docs;
}

async function uploadDocs(idx, docs) {
  const BATCH = 1000;
  let uploaded = 0;

  console.log(`Upload ke temporary index (batch ${BATCH})...`);
  for (let i = 0; i < docs.length; i += BATCH) {
    const chunk = docs.slice(i, i + BATCH);
    await waitTask(idx.addDocuments(chunk), `add documents ${i + 1}-${i + chunk.length}`);
    uploaded += chunk.length;
    console.log(`   [${uploaded}/${docs.length}]`);
  }
}

async function verifyTempIndex(idx, expectedCount) {
  const stats = await idx.getStats();
  console.log("\nTemporary index stats:");
  console.log(`   Total documents : ${stats.numberOfDocuments}`);
  console.log(`   Is indexing     : ${stats.isIndexing}`);

  if (stats.isIndexing) {
    throw new Error("Temporary index masih indexing setelah task upload selesai.");
  }
  if (stats.numberOfDocuments !== expectedCount) {
    throw new Error(
      `Document count mismatch: expected ${expectedCount}, got ${stats.numberOfDocuments}`,
    );
  }
}

async function reindexAll() {
  const products = await fetchProducts();
  const docs = buildDocs(products);

  if (DRY_RUN) {
    console.log("Dry-run: tidak menulis ke Meilisearch.");
    console.log(`Dokumen valid: ${docs.length}`);
    if (docs[0]) {
      console.log(`Sample keys: ${Object.keys(docs[0]).sort().join(", ")}`);
    }
    return;
  }

  const tempIndexName = `${INDEX_NAME}_tmp_${Date.now()}`;
  let swapped = false;

  try {
    console.log(`Create temporary index: ${tempIndexName}`);
    await deleteIndexIfExists(tempIndexName);
    await waitTask(meili.createIndex(tempIndexName, { primaryKey: "id" }), "create temp index");
    const tempIndex = meili.index(tempIndexName);

    console.log("Apply settings to temporary index...");
    await applyProductIndexSettings(tempIndex, { wait: true, waitOptions: WAIT_OPTIONS });

    await uploadDocs(tempIndex, docs);
    await verifyTempIndex(tempIndex, docs.length);

    await ensureIndex(INDEX_NAME);
    console.log(`\nAtomic swap: ${tempIndexName} -> ${INDEX_NAME}`);
    await waitTask(
      meili.swapIndexes([{ indexes: [tempIndexName, INDEX_NAME], rename: true }]),
      "swap indexes",
    );
    swapped = true;

    console.log(`Delete old index now named ${tempIndexName}...`);
    await deleteIndexIfExists(tempIndexName);

    const final = await meili.index(INDEX_NAME).getStats();
    console.log("\nRe-index selesai:");
    console.log(`   Total documents : ${final.numberOfDocuments}`);
    console.log(`   Is indexing     : ${final.isIndexing}`);
  } catch (error) {
    if (!swapped) {
      await deleteIndexIfExists(tempIndexName).catch((cleanupError) => {
        console.error("Cleanup temporary index failed:", cleanupError);
      });
    }
    throw error;
  }
}

async function main() {
  console.log("=".repeat(60));
  console.log("  Reindex Search - Meilisearch");
  console.log("=".repeat(60) + "\n");

  if (DRY_RUN) {
    await reindexAll();
  } else {
    if (!SKIP_SETUP) await setupIndex();
    if (!SETUP_ONLY) await reindexAll();
  }

  console.log("\nDone!");
}

main()
  .catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
