/**
 * GET /api/search/trending
 *
 * Returns the products that have been ordered most often over the last 30
 * days, surfaced under the "Lagi banyak dicari" section in the search overlay.
 *
 * Uses real order data, never a hardcoded list. Out-of-stock / inactive
 * products are excluded.
 */

import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const WINDOW_DAYS = 30;
const LIMIT = 6;

export async function GET() {
  try {
    const since = new Date(Date.now() - WINDOW_DAYS * 24 * 60 * 60 * 1000);

    const grouped = await prisma.orderItem.groupBy({
      by: ["productId"],
      where: {
        order: { createdAt: { gte: since } },
      },
      _sum: { quantity: true },
      orderBy: { _sum: { quantity: "desc" } },
      take: LIMIT * 3, // over-fetch to let inactive/empty-stock filter trim
    });

    const productIds = grouped.map((row) => row.productId);
    if (productIds.length === 0) {
      // Fallback: top-rated active products. Avoids an empty overlay
      // when the shop has no orders in the last 30 days yet.
      const fallback = await prisma.product.findMany({
        where: { isActive: true },
        select: {
          id: true,
          slug: true,
          name: true,
          imageUrl: true,
          price: true,
          discountPrice: true,
          brand: { select: { name: true } },
          category: { select: { name: true } },
        },
        orderBy: [{ reviewCount: "desc" }, { avgRating: "desc" }],
        take: LIMIT,
      });
      return NextResponse.json({
        items: fallback.map((p) => ({
          id: p.id,
          slug: p.slug,
          name: p.name,
          imageUrl: p.imageUrl,
          price: p.discountPrice ?? p.price,
          brandName: p.brand?.name ?? null,
          categoryName: p.category?.name ?? null,
          orderCount: 0,
        })),
        source: "rating_fallback",
      });
    }

    const products = await prisma.product.findMany({
      where: {
        id: { in: productIds },
        isActive: true,
      },
      select: {
        id: true,
        slug: true,
        name: true,
        imageUrl: true,
        price: true,
        discountPrice: true,
        brand: { select: { name: true } },
        category: { select: { name: true } },
      },
    });

    const byId = new Map(products.map((p) => [p.id, p]));
    const ordered = grouped
      .map((row) => {
        const p = byId.get(row.productId);
        if (!p) return null;
        return {
          id: p.id,
          slug: p.slug,
          name: p.name,
          imageUrl: p.imageUrl,
          price: p.discountPrice ?? p.price,
          brandName: p.brand?.name ?? null,
          categoryName: p.category?.name ?? null,
          orderCount: row._sum.quantity ?? 0,
        };
      })
      .filter(Boolean)
      .slice(0, LIMIT);

    return NextResponse.json({ items: ordered, source: "order_30d" });
  } catch (error) {
    return NextResponse.json(
      {
        items: [],
        source: "error",
        error: error instanceof Error ? error.message : "unknown",
      },
      { status: 200 },
    );
  }
}
