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
import { searchProducts, type ProductSearchDoc, type SearchSort } from "@/lib/search";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

const VALID_SORT: SearchSort[] = [
  "relevance",
  "price_asc",
  "price_desc",
  "newest",
  "rating_desc",
  "best_seller",
];

async function enrichSearchItems(items: ProductSearchDoc[]) {
  if (items.length === 0) return items;

  const products = await prisma.product.findMany({
    where: { id: { in: items.map((item) => item.id) } },
    select: {
      id: true,
      discountPrice: true,
      stock: true,
      weightGram: true,
      imageUrl: true,
      isActive: true,
      hasVariants: true,
    },
  });

  const byId = new Map(products.map((product) => [product.id, product]));

  return items.map((item) => {
    const product = byId.get(item.id);
    return {
      ...item,
      discount_price: product?.discountPrice ?? item.discount_price ?? null,
      stock: product?.stock ?? item.stock ?? item.total_stock,
      weight_grams: product?.weightGram ?? item.weight_grams,
      image_url: product?.imageUrl ?? item.image_url,
      is_active: product?.isActive ?? item.is_active ?? true,
      has_variants: product?.hasVariants ?? item.has_variants ?? false,
    };
  });
}

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

    return NextResponse.json({
      ...result,
      items: await enrichSearchItems(result.items as ProductSearchDoc[]),
    });
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
