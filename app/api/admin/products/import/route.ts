/**
 * POST /api/admin/products/import
 *
 * Bulk import produk dari prisma/products_import.json ke database production.
 *
 * Karena Vercel functions punya timeout 30s, import dijalankan per-batch.
 * Client mengirim { offset, batchSize } berulang sampai response.done = true.
 *
 * Pada batch pertama (offset = 0):
 *   - Upsert seluruh categories
 *   - Upsert seluruh brands
 *   - Build map name → id untuk kategori & brand
 *
 * Tiap batch:
 *   - Upsert produk dalam jendela [offset, offset + batchSize)
 *   - Untuk produk dengan varian, upsert VariantAttribute, VariantOption,
 *     ProductVariant, ProductVariantOption
 *
 * Setelah batch terakhir, halaman /products & /products/[slug] di-revalidate
 * agar harga & stok terbaru tampil tanpa harus tunggu cache 60s.
 *
 * Body: { offset?: number; batchSize?: number }
 * Response: {
 *   ok: true,
 *   totalProducts: number,
 *   processedThisCall: number,
 *   processedSoFar: number,
 *   nextOffset: number,
 *   done: boolean,
 *   summary?: { categories, brands, productsUpserted, variantsUpserted, skipped }
 * }
 */
import { NextRequest, NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import importData from "@/prisma/products_import.json";

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

interface CategoryData {
  name: string;
  slug: string;
}

interface BrandData {
  name: string;
  slug: string;
}

interface ImportData {
  categories: CategoryData[];
  brands: BrandData[];
  products: ProductData[];
}

const DEFAULT_BATCH_SIZE = 80;
const MAX_BATCH_SIZE = 200;

export async function POST(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json().catch(() => ({}))) as {
    offset?: number;
    batchSize?: number;
  };
  const offset = Math.max(0, Math.floor(Number(body.offset) || 0));
  const batchSize = Math.min(
    MAX_BATCH_SIZE,
    Math.max(1, Math.floor(Number(body.batchSize) || DEFAULT_BATCH_SIZE)),
  );

  const data = importData as ImportData;
  const totalProducts = data.products.length;

  // Pada batch pertama, sync categories & brands dulu.
  let categoriesCreated = 0;
  let brandsCreated = 0;
  if (offset === 0) {
    for (const cat of data.categories) {
      await prisma.category.upsert({
        where: { slug: cat.slug },
        update: { name: cat.name },
        create: { name: cat.name, slug: cat.slug },
      });
      categoriesCreated++;
    }
    for (const brand of data.brands) {
      await prisma.brand.upsert({
        where: { slug: brand.slug },
        update: { name: brand.name },
        create: { name: brand.name, slug: brand.slug },
      });
      brandsCreated++;
    }
  }

  // Build map name → id setiap call (DB query cepat, dipakai untuk batch ini).
  const [allCategories, allBrands] = await Promise.all([
    prisma.category.findMany({ select: { id: true, slug: true } }),
    prisma.brand.findMany({ select: { id: true, name: true } }),
  ]);
  const categoryIdBySlug = new Map(allCategories.map((c) => [c.slug, c.id]));
  const brandIdByName = new Map(allBrands.map((b) => [b.name, b.id]));

  const slice = data.products.slice(offset, offset + batchSize);
  let productsUpserted = 0;
  let variantsUpserted = 0;
  let skipped = 0;

  for (const prod of slice) {
    if (!prod.name || !prod.slug) {
      skipped++;
      continue;
    }

    const categoryId = categoryIdBySlug.get(prod.category) ?? null;
    const brandId = brandIdByName.get(prod.brand) ?? null;
    const description = generateDescription(prod);

    try {
      const product = await prisma.product.upsert({
        where: { slug: prod.slug },
        update: {
          name: prod.name,
          price: prod.price,
          stock: prod.stock,
          weightGram: prod.weightGram,
          hasVariants: prod.hasVariants,
          isActive: prod.stock > 0,
          categoryId,
          brandId,
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
          categoryId,
          brandId,
          brandAutoAssigned: true,
        },
      });

      if (prod.hasVariants && prod.variants.length > 0) {
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

          let opt = await prisma.variantOption.findFirst({
            where: { attributeId: attr.id, value: label },
          });
          if (!opt) {
            opt = await prisma.variantOption.create({
              data: { attributeId: attr.id, value: label, position: i },
            });
          }

          const sku = `${prod.slug}-${label
            .toLowerCase()
            .replace(/\s+/g, "-")
            .replace(/[^a-z0-9-]/g, "")
            .slice(0, 30)}`;

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

          variantsUpserted++;
        }
      }

      productsUpserted++;
    } catch {
      skipped++;
    }
  }

  const processedSoFar = offset + slice.length;
  const done = processedSoFar >= totalProducts;
  const nextOffset = done ? processedSoFar : processedSoFar;

  // Revalidate halaman public setelah batch terakhir agar harga/stok baru
  // langsung muncul tanpa nunggu ISR cache 60s.
  if (done) {
    revalidatePath("/products");
    revalidatePath("/produk");
  }

  return NextResponse.json({
    ok: true,
    totalProducts,
    processedThisCall: slice.length,
    processedSoFar,
    nextOffset,
    done,
    summary: {
      categoriesUpserted: categoriesCreated,
      brandsUpserted: brandsCreated,
      productsUpserted,
      variantsUpserted,
      skipped,
    },
  });
}

function generateDescription(prod: ProductData): string {
  const brandPart = prod.brand !== "Unknown" ? `${prod.brand} ` : "";
  const weightKg =
    prod.weightGram >= 1000
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
  lines += `Stok: ${
    prod.stock > 0 ? `${prod.stock} tersedia` : "Hubungi kami untuk ketersediaan"
  }`;

  return lines.trim();
}
