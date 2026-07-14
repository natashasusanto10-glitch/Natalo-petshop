/**
 * GET /api/search/trending
 *
 * Search momentum from the last seven days compared with the preceding seven
 * days. A 24-hour boost lets genuinely new demand rise quickly. Low-volume and
 * unsafe queries never reach clients. When there is not enough signal, terms
 * come from the live catalogue (brand -> category -> popular product).
 */

import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  isSearchKeywordAllowed,
  normalizeSearchKeyword,
  rankTrendingKeywords,
  toSearchDisplayLabel,
  type SearchCount,
} from "@/lib/search-trending";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const LIMIT = 6;
const DAY_MS = 24 * 60 * 60 * 1000;

async function groupedCounts(from: Date, to?: Date): Promise<SearchCount[]> {
  const rows = await prisma.searchLog.groupBy({
    by: ["keyword"],
    where: {
      createdAt: {
        gte: from,
        ...(to ? { lt: to } : {}),
      },
    },
    _count: { keyword: true },
    orderBy: { _count: { keyword: "desc" } },
    take: 100,
  });
  const merged = new Map<string, number>();
  for (const row of rows) {
    const keyword = normalizeSearchKeyword(row.keyword);
    merged.set(keyword, (merged.get(keyword) ?? 0) + row._count.keyword);
  }
  return [...merged].map(([keyword, count]) => ({ keyword, count }));
}

async function catalogueFallback(excluded: Set<string>): Promise<string[]> {
  const [brands, categories, products] = await Promise.all([
    prisma.brand.findMany({
      where: { isActive: true, products: { some: { isActive: true } } },
      select: { name: true },
      orderBy: { position: "asc" },
      take: LIMIT * 2,
    }),
    prisma.category.findMany({
      where: { products: { some: { isActive: true } } },
      select: { name: true },
      orderBy: { updatedAt: "desc" },
      take: LIMIT * 2,
    }),
    prisma.product.findMany({
      where: { isActive: true },
      select: { name: true },
      orderBy: [{ reviewCount: "desc" }, { avgRating: "desc" }],
      take: LIMIT * 2,
    }),
  ]);

  const result: string[] = [];
  for (const value of [
    ...brands.map((item) => item.name),
    ...categories.map((item) => item.name),
    ...products.map((item) => item.name),
  ]) {
    const normalized = normalizeSearchKeyword(value);
    if (
      excluded.has(normalized) ||
      !isSearchKeywordAllowed(normalized) ||
      result.some((item) => normalizeSearchKeyword(item) === normalized)
    ) {
      continue;
    }
    result.push(value.trim());
    if (result.length >= LIMIT) break;
  }
  return result;
}

export async function GET() {
  try {
    const now = new Date();
    const currentStart = new Date(now.getTime() - 7 * DAY_MS);
    const previousStart = new Date(now.getTime() - 14 * DAY_MS);
    const recentStart = new Date(now.getTime() - DAY_MS);

    const [current7d, previous7d, recent24h] = await Promise.all([
      groupedCounts(currentStart),
      groupedCounts(previousStart, currentStart),
      groupedCounts(recentStart),
    ]);
    const ranked = rankTrendingKeywords({
      current7d,
      previous7d,
      recent24h,
      limit: LIMIT,
    });

    const terms = ranked.map((item) => toSearchDisplayLabel(item.keyword));
    if (terms.length < LIMIT) {
      const fallback = await catalogueFallback(
        new Set(ranked.map((item) => item.keyword))
      );
      terms.push(...fallback.slice(0, LIMIT - terms.length));
    }

    return NextResponse.json(
      {
        terms,
        items: ranked,
        source: ranked.length > 0 ? "search_momentum" : "catalogue_fallback",
        windows: { recentHours: 24, currentDays: 7, previousDays: 7 },
      },
      {
        headers: {
          "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300",
        },
      },
    );
  } catch (error) {
    return NextResponse.json(
      {
        terms: [],
        items: [],
        source: "error",
        error: error instanceof Error ? error.message : "unknown",
      },
      { status: 200 }
    );
  }
}
