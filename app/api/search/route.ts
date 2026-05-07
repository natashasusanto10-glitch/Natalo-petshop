/**
 * GET /api/search
 *
 * Query params:
 *   q              keyword search (string)
 *   category       category slug — multi-value via repetition (?category=kucing&category=anjing)
 *   brand          brand slug — multi-value
 *   min_price      number
 *   max_price      number
 *   in_stock       "true" | "false"
 *   min_rating     number 1–5
 *   sort           relevance | price_asc | price_desc | newest | rating_desc
 *   page           default 1
 *   per_page       default 24, max 60
 */

import { NextRequest, NextResponse } from "next/server";
import { searchProducts, type SearchSort } from "@/lib/search";

const VALID_SORT: SearchSort[] = [
  "relevance",
  "price_asc",
  "price_desc",
  "newest",
  "rating_desc",
];

export async function GET(request: NextRequest) {
  try {
    const sp = request.nextUrl.searchParams;

    // Validate query length
    const q = (sp.get("q") ?? "").slice(0, 100);

    const sortParam = sp.get("sort") ?? "relevance";
    const sort = VALID_SORT.includes(sortParam as SearchSort)
      ? (sortParam as SearchSort)
      : "relevance";

    let minPrice = sp.get("min_price") ? Number(sp.get("min_price")) : undefined;
    let maxPrice = sp.get("max_price") ? Number(sp.get("max_price")) : undefined;

    // Auto-swap kalau min > max
    if (minPrice !== undefined && maxPrice !== undefined && minPrice > maxPrice) {
      [minPrice, maxPrice] = [maxPrice, minPrice];
    }

    const result = await searchProducts({
      q,
      categorySlug: sp.getAll("category"),
      brandSlug: sp.getAll("brand"),
      minPrice,
      maxPrice,
      inStock: sp.get("in_stock") === "true",
      minRating: sp.get("min_rating")
        ? Number(sp.get("min_rating"))
        : undefined,
      sort,
      page: Math.max(1, Number(sp.get("page") ?? 1)),
      perPage: Math.min(60, Math.max(1, Number(sp.get("per_page") ?? 24))),
    });

    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json(
      {
        error: error instanceof Error ? error.message : "Search failed",
        items: [],
        total: 0,
      },
      { status: 500 }
    );
  }
}
