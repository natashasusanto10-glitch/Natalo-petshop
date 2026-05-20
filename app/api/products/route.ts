import { NextRequest, NextResponse } from "next/server";
import {
  getProducts,
  getProductsCount,
  type NewProductFilter,
  type PopularFilter,
} from "@/lib/products";
import { getSession } from "@/lib/auth";

export const dynamic = "force-dynamic";

const NEW_FILTERS: NewProductFilter[] = [
  "today",
  "this-week",
  "this-month",
  "last-30-days",
  "newest",
];
const POPULAR_FILTERS: PopularFilter[] = [
  "best-seller",
  "trending",
  "most-searched",
  "highest-rating",
  "most-bought",
];

function asNewFilter(value: string | null): NewProductFilter | undefined {
  return value && (NEW_FILTERS as string[]).includes(value)
    ? (value as NewProductFilter)
    : undefined;
}

function asPopularFilter(value: string | null): PopularFilter | undefined {
  return value && (POPULAR_FILTERS as string[]).includes(value)
    ? (value as PopularFilter)
    : undefined;
}

function parsePositiveInt(value: string | null, fallback: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : fallback;
}

function parseBooleanFlag(value: string | null) {
  return value === "1" || value === "true";
}

function parseIdList(value: string | null) {
  return (value ?? "")
    .split(",")
    .map((id) => id.trim())
    .filter(Boolean)
    .slice(0, 100);
}

export async function GET(request: NextRequest) {
  const sp = request.nextUrl.searchParams;
  const limit = Math.min(48, parsePositiveInt(sp.get("limit"), 24));
  const cursor = Math.max(0, parsePositiveInt(sp.get("cursor"), 0));
  const search = (sp.get("search") ?? sp.get("q") ?? "").trim();
  const category = (sp.get("category") ?? sp.get("kategori") ?? "").trim();
  const brand = (sp.get("brand") ?? "").trim();
  const newFilter = asNewFilter(sp.get("new"));
  const popularFilter = asPopularFilter(sp.get("popular"));
  const seed = (sp.get("seed") ?? "").trim().slice(0, 80);
  const excludeIds = parseIdList(sp.get("exclude"));
  const inStockOnly = parseBooleanFlag(sp.get("inStock"));
  const withImageOnly = parseBooleanFlag(sp.get("withImage"));
  const hasPriceOnly = parseBooleanFlag(sp.get("hasPrice"));
  const session = await getSession("CUSTOMER").catch(() => null);

  const [items, total] = await Promise.all([
    getProducts({
      category: category || undefined,
      brand: brand || undefined,
      search: search || undefined,
      newFilter,
      popularFilter,
      randomSeed:
        seed && !category && !brand && !search && !newFilter && !popularFilter ? seed : undefined,
      take: limit,
      skip: cursor,
      excludeIds,
      hasPriceOnly,
      inStockOnly,
      withImageOnly,
      viewerId: session?.sub ?? null,
    }),
    getProductsCount({
      category: category || undefined,
      brand: brand || undefined,
      search: search || undefined,
      newFilter,
      popularFilter,
      excludeIds,
      hasPriceOnly,
      inStockOnly,
      withImageOnly,
    }),
  ]);

  const resolvedTotal = total > 0 ? total : items.length;
  const nextOffset = cursor + items.length;

  return NextResponse.json({
    items,
    nextCursor: nextOffset < resolvedTotal ? String(nextOffset) : null,
    hasMore: nextOffset < resolvedTotal,
    total: resolvedTotal,
  });
}
