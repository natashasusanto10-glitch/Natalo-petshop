/**
 * GET /api/search/facets
 *
 * Return available filter options dengan count produk per opsi.
 * Query params: sama dengan /api/search (kecuali sort, page).
 *
 * Meilisearch facets memakai key stabil (slug), lalu display name di-hydrate
 * dari DB. Nama kategori/brand tidak dijadikan facet key karena bukan source
 * of truth dan tidak perlu masuk filterableAttributes.
 */
import { NextRequest, NextResponse } from "next/server";
import { productIndex, searchProducts } from "@/lib/search";
import { prisma } from "@/lib/prisma";
import { buildWeightBuckets, hydrateFacetDistribution } from "@/lib/search-facets";

export const dynamic = "force-dynamic";

function parseFacetParams(request: NextRequest) {
  const sp = request.nextUrl.searchParams;
  let minPrice = sp.get("min_price") ? Number(sp.get("min_price")) : undefined;
  let maxPrice = sp.get("max_price") ? Number(sp.get("max_price")) : undefined;

  if (minPrice !== undefined && maxPrice !== undefined && minPrice > maxPrice) {
    [minPrice, maxPrice] = [maxPrice, minPrice];
  }

  return {
    q: (sp.get("q") ?? "").slice(0, 100),
    categorySlug: sp.getAll("category"),
    brandSlug: sp.getAll("brand"),
    minPrice,
    maxPrice,
    inStock: sp.get("in_stock") === "true",
    minRating: sp.get("min_rating") ? Number(sp.get("min_rating")) : undefined,
  };
}

function escapeMeiliFilterValue(value: string) {
  return value.replace(/"/g, '\\"');
}

function multiValueFilter(field: string, values: string[]) {
  if (values.length === 0) return null;
  return `(${values.map((value) => `${field} = "${escapeMeiliFilterValue(value)}"`).join(" OR ")})`;
}

function buildMeiliFilter(params: ReturnType<typeof parseFacetParams>) {
  const filters: string[] = ["is_active = true"];

  if (params.minPrice !== undefined && Number.isFinite(params.minPrice)) {
    filters.push(`price_min >= ${Math.max(0, params.minPrice)}`);
  }
  if (params.maxPrice !== undefined && Number.isFinite(params.maxPrice)) {
    filters.push(`price_min <= ${Math.max(0, params.maxPrice)}`);
  }
  if (params.inStock) filters.push("total_stock > 0");
  if (params.minRating !== undefined && Number.isFinite(params.minRating)) {
    filters.push(`avg_rating >= ${params.minRating}`);
  }

  const categoryFilter = multiValueFilter("category_slug", params.categorySlug);
  if (categoryFilter) filters.push(categoryFilter);

  const brandFilter = multiValueFilter("brand_slug", params.brandSlug);
  if (brandFilter) filters.push(brandFilter);

  return filters.join(" AND ");
}

async function facetsFromDb(request: NextRequest) {
  const params = parseFacetParams(request);
  const result = await searchProducts({
    ...params,
    page: 1,
    perPage: 1,
  });

  return result.facets;
}

export async function GET(request: NextRequest) {
  try {
    const params = parseFacetParams(request);
    const result = await productIndex.search(params.q, {
      filter: buildMeiliFilter(params),
      facets: ["category_slug", "brand_slug", "price_min", "weight_grams"],
      limit: 0,
      sort: ["price_min:asc"],
    });

    const categoryDistribution = result.facetDistribution?.category_slug ?? {};
    const brandDistribution = result.facetDistribution?.brand_slug ?? {};
    const [categories, brands] = await Promise.all([
      prisma.category.findMany({
        where: { slug: { in: Object.keys(categoryDistribution) } },
        select: { slug: true, name: true },
      }),
      prisma.brand.findMany({
        where: { slug: { in: Object.keys(brandDistribution) } },
        select: { slug: true, name: true },
      }),
    ]);

    const categoryNames = new Map(categories.map((category) => [category.slug, category.name]));
    const brandNames = new Map(brands.map((brand) => [brand.slug, brand.name]));
    const priceStats = result.facetStats?.price_min;

    return NextResponse.json({
      categories: hydrateFacetDistribution(categoryDistribution, categoryNames),
      brands: hydrateFacetDistribution(brandDistribution, brandNames),
      price_range: priceStats
        ? { min: Math.floor(priceStats.min ?? 0), max: Math.ceil(priceStats.max ?? 0) }
        : { min: 0, max: 10000000 },
      weights: buildWeightBuckets(result.facetDistribution?.weight_grams),
    });
  } catch (error) {
    const fallback = await facetsFromDb(request).catch(() => ({
      categories: [],
      brands: [],
      price_range: { min: 0, max: 10000000 },
      weights: [],
    }));
    return NextResponse.json({
      ...fallback,
      degraded: true,
      error: error instanceof Error ? error.message : "Facets failed",
    });
  }
}
