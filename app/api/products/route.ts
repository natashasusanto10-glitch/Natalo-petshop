import { NextRequest, NextResponse } from "next/server";
import {
  getProducts,
  getProductsCount,
  type NewProductFilter,
  type PopularFilter,
} from "@/lib/products";

export const dynamic = "force-dynamic";

const NEW_FILTERS: NewProductFilter[] = ["today", "this-week", "this-month", "newest"];
const POPULAR_FILTERS: PopularFilter[] = [
  "best-seller",
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

export async function GET(request: NextRequest) {
  const sp = request.nextUrl.searchParams;
  const limit = Math.min(48, parsePositiveInt(sp.get("limit"), 24));
  const cursor = Math.max(0, parsePositiveInt(sp.get("cursor"), 0));
  const search = (sp.get("search") ?? sp.get("q") ?? "").trim();
  const category = (sp.get("category") ?? sp.get("kategori") ?? "").trim();
  const newFilter = asNewFilter(sp.get("new"));
  const popularFilter = asPopularFilter(sp.get("popular"));

  const [items, total] = await Promise.all([
    getProducts({
      category: category || undefined,
      search: search || undefined,
      newFilter,
      popularFilter,
      take: limit,
      skip: cursor,
    }),
    getProductsCount({
      category: category || undefined,
      search: search || undefined,
      newFilter,
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
