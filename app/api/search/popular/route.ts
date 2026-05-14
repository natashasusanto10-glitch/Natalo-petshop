/**
 * GET /api/search/popular
 *
 * Returns the most-searched keywords over the last 7 days, ranked by frequency.
 *
 * If the SearchLog table is empty (e.g. early launch, before any user has
 * searched anything), falls back to active brand names — never returns a
 * hardcoded list.
 */

import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type PopularKeyword = { rank: number; q: string; count: number };

const WINDOW_DAYS = 7;
const LIMIT = 8;

export async function GET() {
  try {
    const since = new Date(Date.now() - WINDOW_DAYS * 24 * 60 * 60 * 1000);

    const grouped = await prisma.searchLog.groupBy({
      by: ["keyword"],
      where: { createdAt: { gte: since } },
      _count: { keyword: true },
      orderBy: { _count: { keyword: "desc" } },
      take: LIMIT,
    });

    const items: PopularKeyword[] = grouped.map((row, idx) => ({
      rank: idx + 1,
      q: row.keyword,
      count: row._count.keyword,
    }));

    if (items.length > 0) {
      return NextResponse.json({ items, source: "search_log" });
    }

    // Fallback: top brands with active products. Better than hardcoding —
    // still real data from the catalog.
    const brands = await prisma.brand.findMany({
      where: {
        isActive: true,
        products: { some: { isActive: true } },
      },
      select: { name: true },
      orderBy: { position: "asc" },
      take: LIMIT,
    });

    return NextResponse.json({
      items: brands.map((b, idx) => ({
        rank: idx + 1,
        q: b.name.toLowerCase(),
        count: 0,
      })),
      source: "brand_fallback",
    });
  } catch (error) {
    return NextResponse.json(
      { items: [], source: "error", error: error instanceof Error ? error.message : "unknown" },
      { status: 200 },
    );
  }
}
