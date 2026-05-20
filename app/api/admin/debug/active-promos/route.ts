/**
 * GET /api/admin/debug/active-promos
 *
 * Diagnostic endpoint — return state semua promo yang seharusnya aktif
 * SAAT INI (server time). Pakai filter yang sama dengan customer-side
 * price calculator (lib/products.ts getProductListInclude).
 *
 * Tujuan: bantu admin diagnose kenapa diskon tidak muncul di toko.
 * Kalau endpoint ini return kosong/sebagian → ada masalah dengan
 * periode promo (mungkin startsAt future, atau endsAt sudah lewat).
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export async function GET() {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const now = new Date();

  // Promo Toko aktif: startsAt <= now < endsAt, isActive=true
  const activePromoToko = await prisma.productDiscount.findMany({
    where: {
      isActive: true,
      startsAt: { lte: now },
      endsAt: { gt: now },
    },
    include: {
      items: {
        include: {
          product: { select: { id: true, name: true, price: true } },
          variant: { select: { id: true, sku: true, price: true } },
        },
      },
    },
  });

  // Promo Toko yang BELUM aktif (future startsAt) — bantu admin lihat
  // kalau promo masih scheduled.
  const upcomingPromoToko = await prisma.productDiscount.findMany({
    where: {
      isActive: true,
      startsAt: { gt: now },
    },
    select: { id: true, name: true, startsAt: true, endsAt: true },
  });

  // Promo Toko yang sudah expired (endsAt < now)
  const expiredPromoToko = await prisma.productDiscount.count({
    where: {
      endsAt: { lt: now },
    },
  });

  // Flash Sale aktif: flashSaleEndsAt > now
  const activeFlashSale = await prisma.product.findMany({
    where: {
      flashSaleEndsAt: { gt: now },
    },
    select: {
      id: true,
      name: true,
      price: true,
      discountPrice: true,
      flashSaleEndsAt: true,
    },
  });

  return NextResponse.json({
    serverTime: now.toISOString(),
    serverTimezone:
      Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
    promoToko: {
      active: activePromoToko.map((p) => ({
        id: p.id,
        name: p.name,
        startsAt: p.startsAt,
        endsAt: p.endsAt,
        itemCount: p.items.length,
        items: p.items.map((it) => ({
          productName: it.product.name,
          productPrice: it.product.price,
          variantSku: it.variant?.sku ?? null,
          variantPrice: it.variant?.price ?? null,
          discountedPrice: it.discountedPrice,
          isItemActive: it.isItemActive,
        })),
      })),
      upcoming: upcomingPromoToko,
      expiredCount: expiredPromoToko,
    },
    flashSale: {
      active: activeFlashSale,
      activeCount: activeFlashSale.length,
    },
  });
}
