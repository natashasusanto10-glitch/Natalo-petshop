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
  // Limit cap dinaikkan 48 → 200. Sebelumnya 48 → customer stuck di
  // 48 produk pertama walau ada 2000+ di DB. Flutter _loadMore
  // increment limit, tapi backend cap nutup. Dengan 200, Flutter bisa
  // ambil sampai 200 per request, plus cursor pagination handle yang
  // lebih banyak.
  const limit = Math.min(200, parsePositiveInt(sp.get("limit"), 24));
  const cursor = Math.max(0, parsePositiveInt(sp.get("cursor"), 0));
  const search = (sp.get("search") ?? sp.get("q") ?? "").trim();
  const category = (sp.get("category") ?? sp.get("kategori") ?? "").trim();
  const brand = (sp.get("brand") ?? "").trim();
  const newFilter = asNewFilter(sp.get("new"));
  const popularFilter = asPopularFilter(sp.get("popular"));
  const seed = (sp.get("seed") ?? "").trim().slice(0, 80);
  const excludeIds = parseIdList(sp.get("exclude"));
  // Filter by ID list — dipakai wishlist supaya bisa fetch hanya
  // produk yang ada di favorit user. Bypass default sort/pagination
  // dan filter inStock supaya produk stok 0 yang di-wishlist tetap
  // muncul (sesuai spec "wishlist boleh lihat stok 0").
  const includeIds = parseIdList(sp.get("ids"));
  const inStockOnly = parseBooleanFlag(sp.get("inStock"));
  const withImageOnly = parseBooleanFlag(sp.get("withImage"));
  const hasPriceOnly = parseBooleanFlag(sp.get("hasPrice"));
  // Filter "sedang diskon" — produk yang Flash Sale aktif atau punya
  // Promo Toko (ProductDiscountItem) aktif. Dipakai Flutter ProductsScreen
  // discountOnly toggle.
  const discountOnly = parseBooleanFlag(sp.get("discountOnly"));
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
      includeIds: includeIds.length > 0 ? includeIds : undefined,
      // Wishlist tidak filter stok — produk stok 0 yang sudah
      // di-wishlist harus tetap visible (sesuai spec).
      hasPriceOnly,
      inStockOnly: includeIds.length > 0 ? false : inStockOnly,
      withImageOnly,
      discountOnly,
      viewerId: session?.sub ?? null,
    }),
    getProductsCount({
      category: category || undefined,
      brand: brand || undefined,
      search: search || undefined,
      newFilter,
      popularFilter,
      excludeIds,
      includeIds: includeIds.length > 0 ? includeIds : undefined,
      hasPriceOnly,
      inStockOnly: includeIds.length > 0 ? false : inStockOnly,
      withImageOnly,
      discountOnly,
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
