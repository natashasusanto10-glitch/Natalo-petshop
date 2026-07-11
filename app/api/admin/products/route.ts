import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import { syncProduct } from "@/lib/search";
import { putVariantsPayloadSchema } from "@/lib/validators/variant-schema";
import { z } from "zod";
import type { Prisma } from "@prisma/client";

// Schema: Create product (extended dari POST sederhana original — sekarang
// support gallery + opsional variants. Backwards compatible: caller lama
// tanpa gallery / variants tetap jalan.
const createProductSchema = z.object({
  name: z.string().trim().min(1).max(200),
  description: z.string().trim().max(5000).optional().default(""),
  price: z.number().int().min(0).max(999_999_999),
  stock: z.number().int().min(0).max(999_999).optional().default(0),
  weightGram: z.number().int().min(1).max(999_999).optional().default(500),
  imageUrl: z.string().trim().optional(),
  gallery: z.array(z.string().trim()).optional().default([]),
  categoryId: z.string().trim().optional(),
  brandId: z.string().trim().optional(),
  isActive: z.boolean().optional().default(true),
  // SKU Induk — opsional, identifier produk single (tanpa varian).
  // Validasi: huruf/angka/_/- saja (consistent dengan ProductVariant.sku).
  sku: z
    .string()
    .trim()
    .max(80)
    .regex(/^[A-Za-z0-9_\-]+$/, "SKU Induk hanya boleh huruf, angka, _ dan -")
    .optional()
    .or(z.literal("")),
  // Variant payload optional. Kalau ada + hasVariants=true, varian
  // di-create dalam transaction yang sama. Reuse validator dari
  // putVariantsPayloadSchema (sub-set untuk struktur attribute+variant).
  hasVariants: z.boolean().optional().default(false),
  attributes: z.array(z.any()).optional().default([]),
  variants: z.array(z.any()).optional().default([]),
});

const MAX_LIMIT = 100;
const DEFAULT_LIMIT = 50;

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const sp = request.nextUrl.searchParams;
  const page = Math.max(1, parseInt(sp.get("page") || "1", 10));
  const limit = Math.min(
    MAX_LIMIT,
    Math.max(1, parseInt(sp.get("limit") || String(DEFAULT_LIMIT), 10))
  );
  const q = sp.get("q")?.trim() ?? "";
  const categorySlug = sp.get("category")?.trim() ?? "";

  // This endpoint is used only for feed-post product tagging, so only
  // active + in-stock products are taggable — including variant products
  // that have at least one active, in-stock variant.
  const where: Prisma.ProductWhereInput = {
    isActive: true,
    OR: [
      { hasVariants: false, stock: { gt: 0 } },
      { hasVariants: true, variants: { some: { isActive: true, stock: { gt: 0 } } } },
    ],
  };
  if (q) where.name = { contains: q, mode: "insensitive" };
  if (categorySlug) where.category = { slug: categorySlug };

  const [products, total] = await Promise.all([
    prisma.product.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * limit,
      take: limit,
      select: {
        id: true,
        name: true,
        price: true,
        stock: true,
        imageUrl: true,
        category: { select: { name: true } },
      },
    }),
    prisma.product.count({ where }),
  ]);

  return NextResponse.json({
    products: products.map((p) => ({
      id: p.id,
      name: p.name,
      price: p.price,
      stock: p.stock,
      imageUrl: p.imageUrl,
      category: p.category?.name ?? "",
    })),
    total,
  });
}

/**
 * POST /api/admin/products
 *
 * Buat produk baru. Dipakai oleh flutter_admin "Tambah Produk Baru" form.
 *
 * Body: {name, price, stock, description?, imageUrl?, weightGram?,
 *        categoryId?, brandId?, isActive?}
 *
 * Auto-generate `slug` dari nama (slugify). Kalau slug tabrakan, append
 * suffix random 4 char.
 */
export async function POST(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const parsed = createProductSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json(
      {
        error: "Payload tidak valid",
        fields: parsed.error.flatten().fieldErrors,
      },
      { status: 400 },
    );
  }
  const body = parsed.data;

  // Kalau hasVariants=true, validate attributes + variants pakai schema
  // yang sama dengan PUT variants endpoint. Kalau false, skip.
  if (body.hasVariants) {
    const variantParsed = putVariantsPayloadSchema.safeParse({
      hasVariants: body.hasVariants,
      attributes: body.attributes,
      variants: body.variants,
    });
    if (!variantParsed.success) {
      // Build issues[] dengan FULL PATH (mis. variants.1.sku) supaya
      // client bisa show detail per-error. `flatten().fieldErrors` cuma
      // capture top-level (variants, attributes) → nested errors dari
      // superRefine custom paths jadi hilang.
      const issues = variantParsed.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      }));
      return NextResponse.json(
        {
          error: "Payload varian tidak valid",
          issues,
          fields: variantParsed.error.flatten().fieldErrors,
        },
        { status: 422 },
      );
    }
  }

  // Slugify nama → lowercase, hyphen, alphanumeric only.
  const baseSlug = body.name
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);

  // Cek konflik slug, append random 4 char kalau tabrakan.
  let slug = baseSlug;
  const existing = await prisma.product.findUnique({ where: { slug } });
  if (existing) {
    const suffix = Math.random().toString(36).slice(2, 6);
    slug = `${baseSlug}-${suffix}`;
  }

  // Atomic create — product + variants dalam satu transaction supaya
  // kalau varian gagal di-create, product juga di-rollback (no orphan).
  const created = await prisma.$transaction(async (tx) => {
    // Validasi SKU Induk unik kalau ada (Product.sku @unique). NULL kalau
    // varian aktif atau kosong — admin tidak isi SKU Induk untuk produk
    // multi-varian (pakai SKU per-varian saja).
    const trimmedSku = body.sku?.trim();
    const productSku = body.hasVariants ? null : trimmedSku || null;
    if (productSku) {
      const existingSku = await tx.product.findFirst({
        where: { sku: productSku },
      });
      if (existingSku) {
        throw new Error(`SKU Induk "${productSku}" sudah digunakan oleh produk lain.`);
      }
    }

    const product = await tx.product.create({
      data: {
        name: body.name.trim(),
        slug,
        sku: productSku,
        description: body.description.trim(),
        price: Math.round(body.price),
        stock: Math.round(body.stock),
        weightGram: Math.round(body.weightGram),
        imageUrl: body.imageUrl?.trim() || null,
        gallery: body.gallery.map((g) => g.trim()).filter(Boolean),
        categoryId: body.categoryId?.trim() || null,
        brandId: body.brandId?.trim() || null,
        isActive: body.isActive,
        hasVariants: body.hasVariants,
        // Produk baru dianggap "baru disentuh admin" → tampil di atas admin list.
        lastEditedAt: new Date(),
      },
      select: {
        id: true,
        name: true,
        slug: true,
        price: true,
        stock: true,
        imageUrl: true,
      },
    });

    // Skip variant creation kalau hasVariants=false.
    if (!body.hasVariants) return product;

    // Build attributes + options. Map "attrPosition:optionValue" → DB id.
    type AttrPayload = {
      name: string;
      position: number;
      options: Array<{ value: string; position: number }>;
    };
    type VariantPayload = {
      optionRefs: string[];
      price: number;
      stock: number;
      weightGram: number;
      sku?: string;
      imageUrl?: string;
      isActive: boolean;
    };

    const attributes = body.attributes as AttrPayload[];
    const variants = body.variants as VariantPayload[];
    const optionRefMap = new Map<string, string>();

    for (const attr of attributes) {
      const createdAttr = await tx.variantAttribute.create({
        data: {
          productId: product.id,
          name: attr.name,
          position: attr.position,
          options: {
            create: attr.options.map((opt) => ({
              value: opt.value,
              position: opt.position,
            })),
          },
        },
        include: { options: true },
      });
      for (const opt of createdAttr.options) {
        optionRefMap.set(`${attr.position}:${opt.value}`, opt.id);
      }
    }

    for (const v of variants) {
      const optionIds = v.optionRefs
        .map((ref) => optionRefMap.get(ref))
        .filter((id): id is string => !!id);
      if (optionIds.length !== v.optionRefs.length) continue;

      if (v.sku) {
        const existingSku = await tx.productVariant.findFirst({
          where: { sku: v.sku },
        });
        if (existingSku) {
          throw new Error(`SKU "${v.sku}" sudah digunakan oleh varian lain.`);
        }
      }

      await tx.productVariant.create({
        data: {
          productId: product.id,
          sku: v.sku || null,
          price: v.price,
          stock: v.stock,
          weightGram: v.weightGram,
          imageUrl: v.imageUrl || null,
          isActive: v.isActive,
          options: {
            create: optionIds.map((optionId) => ({ optionId })),
          },
        },
      });
    }

    // Sync aggregate field di Product dari varian aktif:
    // - price = harga TERMURAH varian aktif
    // - stock = TOTAL stok semua varian aktif
    // - weightGram = berat varian termurah (representasi default)
    const activeVariants = await tx.productVariant.findMany({
      where: { productId: product.id, deletedAt: null, isActive: true },
      select: { price: true, stock: true, weightGram: true },
    });
    if (activeVariants.length > 0) {
      const prices = activeVariants.map((v) => v.price);
      const minPrice = Math.min(...prices);
      const cheapest = activeVariants.find((v) => v.price === minPrice)!;
      const totalStock = activeVariants.reduce((s, v) => s + v.stock, 0);
      const updated = await tx.product.update({
        where: { id: product.id },
        data: {
          price: minPrice,
          stock: totalStock,
          weightGram: cheapest.weightGram,
        },
        select: {
          id: true,
          name: true,
          slug: true,
          price: true,
          stock: true,
          imageUrl: true,
        },
      });
      return updated;
    }

    return product;
  });

  // Sync search index (non-blocking).
  syncProduct(created.id).catch((err) => {
    console.error("[admin/products POST syncProduct]", err);
  });

  return NextResponse.json(created, { status: 201 });
}
