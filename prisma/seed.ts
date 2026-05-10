import { PrismaClient } from "@prisma/client";
import * as fs from "fs";
import * as path from "path";

const prisma = new PrismaClient();

interface CategoryData {
  name: string;
  slug: string;
}

interface BrandData {
  name: string;
  slug: string;
}

interface VariantData {
  label: string;
  price: number;
  stock: number;
  weightGram: number;
}

interface ProductData {
  name: string;
  slug: string;
  brand: string;
  category: string;
  price: number;
  stock: number;
  weightGram: number;
  hasVariants: boolean;
  variants: VariantData[];
}

interface ImportData {
  categories: CategoryData[];
  brands: BrandData[];
  products: ProductData[];
}

async function main() {
  console.log("🚀 Memulai import produk dari Excel...\n");

  // Load data dari JSON
  const dataPath = path.join(__dirname, "products_import.json");
  const raw = fs.readFileSync(dataPath, "utf-8");
  const data: ImportData = JSON.parse(raw);

  console.log(`📦 Data yang akan diimport:`);
  console.log(`   - ${data.categories.length} kategori`);
  console.log(`   - ${data.brands.length} brand`);
  console.log(`   - ${data.products.length} produk\n`);

  // ── 1. Upsert Categories ──────────────────────────────────────────
  console.log("📂 Membuat kategori...");
  const categoryMap: Record<string, string> = {};

  for (const cat of data.categories) {
    const result = await prisma.category.upsert({
      where: { slug: cat.slug },
      update: { name: cat.name },
      create: { name: cat.name, slug: cat.slug },
    });
    categoryMap[cat.slug] = result.id;
  }
  console.log(`   ✅ ${data.categories.length} kategori selesai\n`);

  // ── 2. Upsert Brands ─────────────────────────────────────────────
  console.log("🏷️  Membuat brand...");
  const brandMap: Record<string, string> = {};
  let brandCount = 0;

  for (const brand of data.brands) {
    const result = await prisma.brand.upsert({
      where: { slug: brand.slug },
      update: { name: brand.name },
      create: { name: brand.name, slug: brand.slug },
    });
    brandMap[brand.name] = result.id;
    brandCount++;
    if (brandCount % 50 === 0) {
      console.log(`   ... ${brandCount}/${data.brands.length} brand`);
    }
  }
  console.log(`   ✅ ${data.brands.length} brand selesai\n`);

  // ── 3. Upsert Products ───────────────────────────────────────────
  console.log("🛒 Membuat produk...");
  let productCount = 0;
  let skipCount = 0;
  let variantCount = 0;

  for (const prod of data.products) {
    if (!prod.name || !prod.slug) {
      skipCount++;
      continue;
    }

    const categoryId = categoryMap[prod.category] ?? undefined;
    const brandId = brandMap[prod.brand] ?? undefined;

    // Generate deskripsi otomatis
    const description = generateDescription(prod);

    try {
      const product = await prisma.product.upsert({
        where: { slug: prod.slug },
        update: {
          price: prod.price,
          stock: prod.stock,
          weightGram: prod.weightGram,
          hasVariants: prod.hasVariants,
          categoryId: categoryId ?? null,
          brandId: brandId ?? null,
          brandAutoAssigned: true,
        },
        create: {
          name: prod.name,
          slug: prod.slug,
          description,
          price: prod.price,
          stock: prod.stock,
          weightGram: prod.weightGram,
          hasVariants: prod.hasVariants,
          isActive: prod.stock > 0,
          categoryId: categoryId ?? null,
          brandId: brandId ?? null,
          brandAutoAssigned: true,
        },
      });

      // Buat varian jika ada
      if (prod.hasVariants && prod.variants.length > 0) {
        // Buat VariantAttribute "Varian" (findFirst + create)
        let attr = await prisma.variantAttribute.findFirst({
          where: { productId: product.id, name: "Varian" },
        });
        if (!attr) {
          attr = await prisma.variantAttribute.create({
            data: { productId: product.id, name: "Varian", position: 0 },
          });
        }

        for (let i = 0; i < prod.variants.length; i++) {
          const v = prod.variants[i];
          const label = v.label || `Varian ${i + 1}`;

          // Buat VariantOption (findFirst + create)
          let opt = await prisma.variantOption.findFirst({
            where: { attributeId: attr.id, value: label },
          });
          if (!opt) {
            opt = await prisma.variantOption.create({
              data: { attributeId: attr.id, value: label, position: i },
            });
          }

          // Buat ProductVariant
          const sku = `${prod.slug}-${label.toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9-]/g, "").slice(0, 30)}`;
          const pv = await prisma.productVariant.upsert({
            where: { sku },
            update: {
              price: v.price,
              stock: v.stock,
              weightGram: v.weightGram,
              isActive: v.stock > 0,
            },
            create: {
              productId: product.id,
              sku,
              price: v.price,
              stock: v.stock,
              weightGram: v.weightGram,
              isActive: v.stock > 0,
            },
          });

          // Link ProductVariant ↔ VariantOption
          await prisma.productVariantOption.upsert({
            where: {
              variantId_optionId: {
                variantId: pv.id,
                optionId: opt.id,
              },
            },
            update: {},
            create: {
              variantId: pv.id,
              optionId: opt.id,
            },
          });

          variantCount++;
        }
      }

      productCount++;
      if (productCount % 100 === 0) {
        console.log(`   ... ${productCount}/${data.products.length} produk`);
      }
    } catch (err) {
      console.error(`   ⚠️  Skip produk "${prod.name}":`, (err as Error).message.split("\n")[0]);
      skipCount++;
    }
  }

  console.log(`\n✅ Import selesai!`);
  console.log(`   📦 Produk berhasil: ${productCount}`);
  console.log(`   🎨 Varian dibuat:   ${variantCount}`);
  console.log(`   ⚠️  Produk dilewati: ${skipCount}`);

  // ── 4. Voucher default ───────────────────────────────────────────
  await prisma.voucher.upsert({
    where: { code: "MEMBER10" },
    update: {},
    create: {
      code: "MEMBER10",
      description: "Diskon 10% untuk pembelian pertama member.",
      discountPercent: 10,
      minimumOrder: 50000,
    },
  });
}

function generateDescription(prod: ProductData): string {
  const brandPart = prod.brand !== "Unknown" ? `${prod.brand} ` : "";
  const weightKg = prod.weightGram >= 1000
    ? `${(prod.weightGram / 1000).toFixed(1)} kg`
    : `${prod.weightGram} gram`;

  let lines = `${brandPart}${prod.name}\n\n`;

  if (prod.hasVariants && prod.variants.length > 0) {
    lines += `Tersedia dalam ${prod.variants.length} varian:\n`;
    for (const v of prod.variants) {
      if (v.label) {
        lines += `- ${v.label} — Rp${v.price.toLocaleString("id-ID")}\n`;
      }
    }
    lines += "\n";
  }

  lines += `Berat produk: ${weightKg}\n`;
  lines += `Stok: ${prod.stock > 0 ? `${prod.stock} tersedia` : "Hubungi kami untuk ketersediaan"}`;

  return lines.trim();
}

main()
  .then(async () => {
    await prisma.$disconnect();
  })
  .catch(async (e) => {
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });
