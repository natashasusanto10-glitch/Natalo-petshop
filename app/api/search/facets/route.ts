/**
 * GET /api/search/facets
 *
 * Return available filter options dengan count produk per opsi.
 * Query params: sama dengan /api/search (kecuali sort, page).
 *
 * Response:
 *   categories[], brands[], price_range, weights[]
 */
import { NextRequest, NextResponse } from "next/server";
import { productIndex } from "@/lib/search";

export async function GET(request: NextRequest) {
  try {
    const sp = request.nextUrl.searchParams;
    const q = (sp.get("q") ?? "").slice(0, 100);
    const categorySlug = sp.getAll("category");
    const brandSlug = sp.getAll("brand");
    const minPrice = sp.get("min_price") ? Number(sp.get("min_price")) : undefined;
    const maxPrice = sp.get("max_price") ? Number(sp.get("max_price")) : undefined;
    const inStock = sp.get("in_stock") === "true";
    const minRating = sp.get("min_rating") ? Number(sp.get("min_rating")) : undefined;

    // Build base filter (tidak include kategori/brand karena facets-nya yang kasih distribusi)
    const baseFilters: string[] = ["is_active = true"];
    if (minPrice !== undefined && Number.isFinite(minPrice)) {
      baseFilters.push(`price_min >= ${Math.max(0, minPrice)}`);
    }
    if (maxPrice !== undefined && Number.isFinite(maxPrice)) {
      baseFilters.push(`price_min <= ${Math.max(0, maxPrice)}`);
    }
    if (inStock) baseFilters.push("total_stock > 0");
    if (minRating !== undefined && Number.isFinite(minRating)) {
      baseFilters.push(`avg_rating >= ${minRating}`);
    }

    // Untuk facet kategori: include filter brand
    const filterForCategoryFacet = [...baseFilters];
    if (brandSlug.length > 0) {
      const escaped = brandSlug.map((b) => `brand_slug = "${b.replace(/"/g, '\\"')}"`);
      filterForCategoryFacet.push(`(${escaped.join(" OR ")})`);
    }

    // Untuk facet brand: include filter kategori
    const filterForBrandFacet = [...baseFilters];
    if (categorySlug.length > 0) {
      const escaped = categorySlug.map((c) => `category_slug = "${c.replace(/"/g, '\\"')}"`);
      filterForBrandFacet.push(`(${escaped.join(" OR ")})`);
    }

    // Untuk price range: include semua filter
    const fullFilter = [
      ...baseFilters,
      ...(categorySlug.length > 0
        ? [`(${categorySlug.map((c) => `category_slug = "${c.replace(/"/g, '\\"')}"`).join(" OR ")})`]
        : []),
      ...(brandSlug.length > 0
        ? [`(${brandSlug.map((b) => `brand_slug = "${b.replace(/"/g, '\\"')}"`).join(" OR ")})`]
        : []),
    ];

    // Eksekusi 3 query parallel
    const [catResult, brandResult, priceResult] = await Promise.all([
      productIndex.search(q, {
        filter: filterForCategoryFacet.join(" AND "),
        facets: ["category_slug", "category_name"],
        limit: 0,
      }),
      productIndex.search(q, {
        filter: filterForBrandFacet.join(" AND "),
        facets: ["brand_slug", "brand_name"],
        limit: 0,
      }),
      productIndex.search(q, {
        filter: fullFilter.join(" AND "),
        facets: ["weight_grams"],
        limit: 0,
        sort: ["price_min:asc"],
      }),
    ]);

    // Aggregate categories
    const catSlugs = catResult.facetDistribution?.category_slug ?? {};
    const catNames = catResult.facetDistribution?.category_name ?? {};
    const categories = Object.entries(catSlugs)
      .filter(([, count]) => count > 0)
      .map(([slug, count]) => {
        const name = Object.entries(catNames).find(([, c]) => c === count)?.[0] ?? slug;
        return { slug, name, count };
      })
      .sort((a, b) => b.count - a.count);

    // Aggregate brands
    const brandSlugs = brandResult.facetDistribution?.brand_slug ?? {};
    const brandNames = brandResult.facetDistribution?.brand_name ?? {};
    const brands = Object.entries(brandSlugs)
      .filter(([, count]) => count > 0)
      .map(([slug, count]) => {
        const name = Object.entries(brandNames).find(([, c]) => c === count)?.[0] ?? slug;
        return { slug, name, count };
      })
      .sort((a, b) => b.count - a.count);

    // Price range stats — cari min/max dari hasil
    const stats = priceResult.facetStats?.weight_grams;
    void stats;
    // Untuk price_min: ambil dari Meilisearch facetStats kalau ada
    // Atau hitung manual dari sample (limit kecil)
    const priceStats = priceResult.facetStats?.price_min;
    const priceRange = priceStats
      ? { min: Math.floor(priceStats.min ?? 0), max: Math.ceil(priceStats.max ?? 0) }
      : { min: 0, max: 10000000 };

    // Weight buckets
    const weightDist = priceResult.facetDistribution?.weight_grams ?? {};
    const allWeights = Object.entries(weightDist)
      .map(([w, c]) => ({ weight: Number(w), count: c }))
      .filter((w) => Number.isFinite(w.weight));

    const weightBuckets = [
      {
        label: "< 1 KG",
        min: 0,
        max: 999,
        count: allWeights.filter((w) => w.weight < 1000).reduce((s, w) => s + w.count, 0),
      },
      {
        label: "1 - 5 KG",
        min: 1000,
        max: 5000,
        count: allWeights
          .filter((w) => w.weight >= 1000 && w.weight <= 5000)
          .reduce((s, w) => s + w.count, 0),
      },
      {
        label: "> 5 KG",
        min: 5001,
        max: 999999,
        count: allWeights.filter((w) => w.weight > 5000).reduce((s, w) => s + w.count, 0),
      },
    ];

    return NextResponse.json({
      categories,
      brands,
      price_range: priceRange,
      weights: weightBuckets,
    });
  } catch (error) {
    return NextResponse.json(
      {
        error: error instanceof Error ? error.message : "Facets failed",
        categories: [],
        brands: [],
        price_range: { min: 0, max: 10000000 },
        weights: [],
      },
      { status: 200 }
    );
  }
}
