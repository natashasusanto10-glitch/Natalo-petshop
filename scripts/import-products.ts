/**
 * Import produk dari products_final.json ke database.
 * Jalankan: npx tsx scripts/import-products.ts
 *
 * Aturan:
 * - Upsert by slug (tidak duplikat jika dijalankan ulang)
 * - Deskripsi dari needs_manual_review.json menimpa products_final.json untuk 156 produk terkait
 * - price / stock / weightGram = 0
 * - imageUrl = /uploads/{filename} dari gambar dengan is_primary: true
 * - Kategori diambil dari DB (harus sudah ada)
 */

import path from "path";
import fs from "fs";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

const PRODUCTS_FILE = path.resolve("C:/Users/USER/Desktop/products_final.json");
const REVIEW_FILE = path.resolve("C:/Users/USER/Desktop/needs_manual_review.json");
const BATCH_SIZE = 50;

type RawProduct = {
  id: number;
  sku: string | null;
  name: string;
  slug: string;
  category: string;
  price: null;
  stock: null;
  weight_grams: null;
  description: string;
  images: { filename: string; source_url: string; is_primary: boolean; position: number }[];
  shopee_product_id: string;
  description_source: string;
};

type ReviewProduct = {
  id: number;
  name: string;
  category: string;
  new_description: string;
};

async function main() {
  console.log("Membaca file JSON...");
  const products: RawProduct[] = JSON.parse(fs.readFileSync(PRODUCTS_FILE, "utf-8"));
  const reviewList: ReviewProduct[] = JSON.parse(fs.readFileSync(REVIEW_FILE, "utf-8"));

  // Map id → new_description untuk override
  const descOverride = new Map<number, string>(
    reviewList.map((p) => [p.id, p.new_description])
  );

  // Ambil semua kategori dari DB
  console.log("Memuat kategori dari database...");
  const categories = await prisma.category.findMany({ select: { id: true, name: true } });
  const categoryMap = new Map<string, string>(categories.map((c) => [c.name, c.id]));

  const missingCats = new Set<string>();
  for (const p of products) {
    if (p.category && !categoryMap.has(p.category)) missingCats.add(p.category);
  }
  if (missingCats.size > 0) {
    console.warn("⚠️  Kategori tidak ditemukan di DB (akan diset null):", [...missingCats]);
  }

  console.log(`Mulai import ${products.length} produk...`);
  let created = 0;
  let updated = 0;
  let errors = 0;

  for (let i = 0; i < products.length; i += BATCH_SIZE) {
    const batch = products.slice(i, i + BATCH_SIZE);

    await Promise.all(
      batch.map(async (p) => {
        try {
          const description = descOverride.get(p.id) ?? p.description;
          const categoryId = categoryMap.get(p.category) ?? null;
          const primaryImage = p.images.find((img) => img.is_primary) ?? p.images[0];
          const imageUrl = primaryImage ? `/uploads/products/${primaryImage.filename}` : null;

          const result = await prisma.product.upsert({
            where: { slug: p.slug },
            create: {
              name: p.name,
              slug: p.slug,
              description,
              price: 0,
              stock: 0,
              weightGram: 0,
              imageUrl,
              isActive: true,
              hasVariants: false,
              categoryId,
            },
            update: {
              name: p.name,
              description,
              imageUrl,
              categoryId,
            },
            select: { id: true },
          });

          // Hitung created vs updated berdasarkan apakah slug sudah ada
          void result;
          created++; // disederhanakan — upsert tidak kembalikan info ini secara native
        } catch (err) {
          errors++;
          console.error(`❌ Gagal: [id=${p.id}] ${p.name.slice(0, 60)}`, err);
        }
      })
    );

    const done = Math.min(i + BATCH_SIZE, products.length);
    process.stdout.write(`\r  Progress: ${done}/${products.length}`);
  }

  console.log(`\n\n✅ Selesai!`);
  console.log(`   Total produk di file : ${products.length}`);
  console.log(`   Produk di-upsert     : ${created}`);
  console.log(`   Override deskripsi   : ${descOverride.size}`);
  console.log(`   Error                : ${errors}`);
}

main()
  .catch((err) => {
    console.error("Fatal:", err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
