import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";
import type { Prisma } from "@prisma/client";

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
  const stockStatus = sp.get("stock_status")?.trim() ?? "";

  const where: Prisma.ProductWhereInput = { hasVariants: false };
  if (q) where.name = { contains: q, mode: "insensitive" };
  if (categorySlug) where.category = { slug: categorySlug };
  if (stockStatus === "empty") where.stock = 0;
  else if (stockStatus === "low") where.stock = { gt: 0, lte: 5 };

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

  const body = (await request.json().catch(() => null)) as
    | {
        name?: string;
        description?: string;
        price?: number;
        stock?: number;
        weightGram?: number;
        imageUrl?: string;
        categoryId?: string;
        brandId?: string;
        isActive?: boolean;
      }
    | null;

  if (!body || typeof body.name !== "string" || !body.name.trim()) {
    return NextResponse.json(
      { error: "Nama produk wajib diisi" },
      { status: 400 },
    );
  }
  if (typeof body.price !== "number" || body.price < 0) {
    return NextResponse.json(
      { error: "Harga harus angka >= 0" },
      { status: 400 },
    );
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

  const product = await prisma.product.create({
    data: {
      name: body.name.trim(),
      slug,
      description: body.description?.trim() ?? "",
      price: Math.round(body.price),
      stock: body.stock && body.stock >= 0 ? Math.round(body.stock) : 0,
      weightGram:
        body.weightGram && body.weightGram > 0
          ? Math.round(body.weightGram)
          : 500,
      imageUrl: body.imageUrl?.trim() || null,
      categoryId: body.categoryId?.trim() || null,
      brandId: body.brandId?.trim() || null,
      isActive: body.isActive !== false,
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

  return NextResponse.json(product, { status: 201 });
}
