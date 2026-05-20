/**
 * GET /api/admin/discounts/promo-toko/eligible-products
 *
 * Query parameters:
 *  - q          : search string (nama produk)
 *  - categoryId : filter by category
 *  - excludeId  : ID promo yang sedang di-edit (untuk include produknya)
 *
 * Return produk yang ELIGIBLE untuk di-tag ke Promo Toko baru:
 *  - Aktif (isActive=true)
 *  - TIDAK sedang masuk Promo Toko lain yang aktif/upcoming
 *  - KECUALI promo yang sedang di-edit (excludeId) — produk yang sudah
 *    masuk promo itu tetap eligible supaya admin bisa lihat di edit form.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const sp = request.nextUrl.searchParams;
  const q = sp.get("q")?.trim() ?? "";
  const categoryId = sp.get("categoryId")?.trim() ?? "";
  const excludeId = sp.get("excludeId")?.trim() ?? "";

  // Cari semua produk yang sedang di Promo Toko aktif/upcoming.
  const now = new Date();
  const activePromos = await prisma.productDiscount.findMany({
    where: {
      isActive: true,
      endsAt: { gt: now },
      ...(excludeId ? { id: { not: excludeId } } : {}),
    },
    select: { productIds: true },
  });
  const blockedProductIds = new Set<string>();
  for (const p of activePromos) {
    for (const pid of p.productIds) blockedProductIds.add(pid);
  }

  const where: {
    isActive: boolean;
    name?: { contains: string; mode: "insensitive" };
    categoryId?: string;
    id?: { notIn: string[] };
  } = { isActive: true };
  if (q) where.name = { contains: q, mode: "insensitive" };
  if (categoryId) where.categoryId = categoryId;
  if (blockedProductIds.size > 0) {
    where.id = { notIn: Array.from(blockedProductIds) };
  }

  const products = await prisma.product.findMany({
    where,
    orderBy: { name: "asc" },
    take: 200,
    select: {
      id: true,
      name: true,
      imageUrl: true,
      price: true,
      stock: true,
      category: { select: { name: true } },
    },
  });

  return NextResponse.json({ products });
}
