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
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

function normalizeSearchText(value: string) {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function tokensFor(query: string) {
  return normalizeSearchText(query)
    .split(/\s+/)
    .filter((token) => token.length >= 2);
}

function productSearchOr(query: string) {
  if (!query) return undefined;
  const tokens = tokensFor(query);
  return [
    { name: { contains: query, mode: "insensitive" as const } },
    { description: { contains: query, mode: "insensitive" as const } },
    { category: { name: { contains: query, mode: "insensitive" as const } } },
    { brand: { name: { contains: query, mode: "insensitive" as const } } },
    ...tokens.flatMap((token) => [
      { name: { contains: token, mode: "insensitive" as const } },
      { description: { contains: token, mode: "insensitive" as const } },
      { category: { name: { contains: token, mode: "insensitive" as const } } },
      { brand: { name: { contains: token, mode: "insensitive" as const } } },
    ]),
  ];
}

async function facetsFromDb(request: NextRequest) {
  const sp = request.nextUrl.searchParams;
  const q = (sp.get("q") ?? "").trim().slice(0, 100);
  const categorySlug = sp.getAll("category");
  const brandSlug = sp.getAll("brand");
  const minPrice = sp.get("min_price") ? Number(sp.get("min_price")) : undefined;
  const maxPrice = sp.get("max_price") ? Number(sp.get("max_price")) : undefined;
  const inStock = sp.get("in_stock") === "true";
  const minRating = sp.get("min_rating") ? Number(sp.get("min_rating")) : undefined;
  const searchOr = productSearchOr(q);

  const products = await prisma.product.findMany({
    where: {
      isActive: true,
      ...(searchOr ? { OR: searchOr } : {}),
      ...(categorySlug.length > 0 ? { category: { slug: { in: categorySlug } } } : {}),
      ...(brandSlug.length > 0 ? { brand: { slug: { in: brandSlug } } } : {}),
      ...(minPrice !== undefined && Number.isFinite(minPrice)
        ? { price: { gte: Math.max(0, minPrice) } }
        : {}),
      ...(maxPrice !== undefined && Number.isFinite(maxPrice)
        ? { price: { lte: Math.max(0, maxPrice) } }
        : {}),
      ...(inStock ? { stock: { gt: 0 } } : {}),
      ...(minRating !== undefined && Number.isFinite(minRating)
        ? { avgRating: { gte: minRating } }
        : {}),
    },
    include: {
      category: { select: { slug: true, name: true } },
      brand: { select: { slug: true, name: true } },
      variants: {
        where: { deletedAt: null, isActive: true },
        select: { price: true, stock: true, weightGram: true },
      },
    },
  });

  const categoryMap = new Map<string, { slug: string; name: string; count: number }>();
  const brandMap = new Map<string, { slug: string; name: string; count: number }>();
  const prices: number[] = [];
  const weights: number[] = [];

  for (const product of products) {
    if (product.category) {
      const prev = categoryMap.get(product.category.slug);
      categoryMap.set(product.category.slug, {
        slug: product.category.slug,
        name: product.category.name,
        count: (prev?.count ?? 0) + 1,
      });
    }
    if (product.brand) {
      const prev = brandMap.get(product.brand.slug);
      brandMap.set(product.brand.slug, {
        slug: product.brand.slug,
        name: product.brand.name,
        count: (prev?.count ?? 0) + 1,
      });
    }

    if (product.hasVariants && product.variants.length) {
      prices.push(...product.variants.map((variant) => variant.price));
      weights.push(...product.variants.map((variant) => variant.weightGram));
    } else {
      prices.push(product.discountPrice && product.discountPrice < product.price
        ? product.discountPrice
        : product.price);
      weights.push(product.weightGram);
    }
  }

  const countWeights = (predicate: (weight: number) => boolean) =>
    weights.filter(predicate).length;

  return {
    categories: Array.from(categoryMap.values()).sort((a, b) => b.count - a.count),
    brands: Array.from(brandMap.values()).sort((a, b) => b.count - a.count),
    price_range: {
      min: prices.length ? Math.min(...prices) : 0,
      max: prices.length ? Math.max(...prices) : 10000000,
    },
    weights: [
      { label: "< 1 KG", min: 0, max: 999, count: countWeights((weight) => weight < 1000) },
      {
        label: "1 - 5 KG",
        min: 1000,
        max: 5000,
        count: countWeights((weight) => weight >= 1000 && weight <= 5000),
      },
      { label: "> 5 KG", min: 5001, max: 999999, count: countWeights((weight) => weight > 5000) },
    ],
  };
}

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
        facets: ["price_min", "weight_grams"],
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
