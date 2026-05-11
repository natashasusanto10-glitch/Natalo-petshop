/**
 * GET /api/search/suggest?q=...&limit=8
 *
 * Auto-suggest untuk dropdown search. Data berasal dari Meilisearch bila
 * tersedia, lalu dilengkapi fallback database agar UI tetap hidup saat search
 * engine lokal/offline.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { productIndex } from "@/lib/search";

export const dynamic = "force-dynamic";

type SuggestProduct = {
  id: string;
  slug: string;
  name: string;
  image_url: string | null;
  price_min: number;
  price_max: number;
  brand_name: string | null;
};

type SuggestResponse = {
  products: SuggestProduct[];
  categories: Array<{ slug: string; name: string; count: number }>;
  brands: Array<{ slug: string; name: string; count: number }>;
  total: number;
};

const EMPTY: SuggestResponse = {
  products: [],
  categories: [],
  brands: [],
  total: 0,
};

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

function tokenWhere(token: string) {
  return [
    { name: { contains: token, mode: "insensitive" as const } },
    { description: { contains: token, mode: "insensitive" as const } },
    { category: { name: { contains: token, mode: "insensitive" as const } } },
    { brand: { name: { contains: token, mode: "insensitive" as const } } },
    { variants: { some: { sku: { contains: token, mode: "insensitive" as const } } } },
  ];
}

function scoreLabel(label: string, query: string) {
  const normalizedLabel = normalizeSearchText(label);
  const normalizedQuery = normalizeSearchText(query);
  const tokens = tokensFor(query);

  let score = 0;
  if (normalizedLabel === normalizedQuery) score += 100;
  if (normalizedLabel.startsWith(normalizedQuery)) score += 70;
  if (normalizedLabel.includes(normalizedQuery)) score += 50;
  for (const token of tokens) {
    if (normalizedLabel.includes(token)) score += 10;
  }
  return score;
}

function mergeUnique<T extends { slug?: string; id?: string }>(
  first: T[],
  second: T[],
  limit: number,
) {
  const seen = new Set<string>();
  const merged: T[] = [];

  for (const item of [...first, ...second]) {
    const key = item.id ?? item.slug;
    if (!key || seen.has(key)) continue;
    seen.add(key);
    merged.push(item);
    if (merged.length >= limit) break;
  }

  return merged;
}

async function suggestFromMeili(q: string, limit: number): Promise<SuggestResponse> {
  const result = await productIndex.search(q, {
    filter: "is_active = true",
    limit,
    attributesToRetrieve: [
      "id",
      "slug",
      "name",
      "image_url",
      "price_min",
      "price_max",
      "brand_name",
      "brand_slug",
      "category_name",
      "category_slug",
    ],
    facets: ["category_slug", "category_name", "brand_slug", "brand_name"],
  });

  type Hit = SuggestProduct & {
    category_name: string | null;
    category_slug: string | null;
    brand_slug: string | null;
  };

  const hits = result.hits as Hit[];
  const categoryMap = new Map<string, { slug: string; name: string; count: number }>();
  const brandMap = new Map<string, { slug: string; name: string; count: number }>();

  for (const hit of hits) {
    if (hit.category_slug && hit.category_name) {
      const prev = categoryMap.get(hit.category_slug);
      categoryMap.set(hit.category_slug, {
        slug: hit.category_slug,
        name: hit.category_name,
        count: (prev?.count ?? 0) + 1,
      });
    }
    if (hit.brand_slug && hit.brand_name) {
      const prev = brandMap.get(hit.brand_slug);
      brandMap.set(hit.brand_slug, {
        slug: hit.brand_slug,
        name: hit.brand_name,
        count: (prev?.count ?? 0) + 1,
      });
    }
  }

  return {
    products: hits.slice(0, 5),
    categories: Array.from(categoryMap.values()).slice(0, 5),
    brands: Array.from(brandMap.values()).slice(0, 5),
    total: result.estimatedTotalHits ?? hits.length,
  };
}

async function suggestFromDb(q: string, limit: number): Promise<SuggestResponse> {
  const tokens = tokensFor(q);
  const productOr = [
    { name: { contains: q, mode: "insensitive" as const } },
    { description: { contains: q, mode: "insensitive" as const } },
    { category: { name: { contains: q, mode: "insensitive" as const } } },
    { brand: { name: { contains: q, mode: "insensitive" as const } } },
    ...tokens.flatMap(tokenWhere),
  ];
  const labelOr = [
    { name: { contains: q, mode: "insensitive" as const } },
    ...tokens.map((token) => ({ name: { contains: token, mode: "insensitive" as const } })),
  ];

  const [products, categories, brands] = await Promise.all([
    prisma.product.findMany({
      where: { isActive: true, OR: productOr },
      include: {
        brand: { select: { name: true } },
        variants: {
          where: { deletedAt: null, isActive: true },
          select: { price: true, stock: true },
        },
      },
      take: Math.max(limit * 4, 12),
    }),
    prisma.category.findMany({
      where: { OR: labelOr },
      include: { _count: { select: { products: true } } },
      take: 10,
    }),
    prisma.brand.findMany({
      where: { OR: labelOr },
      include: { _count: { select: { products: true } } },
      take: 10,
    }),
  ]);

  const productSuggestions = products
    .sort((a, b) => scoreLabel(b.name, q) - scoreLabel(a.name, q))
    .slice(0, 5)
    .map((product) => {
      const prices = product.hasVariants && product.variants.length
        ? product.variants.map((variant) => variant.price)
        : [product.discountPrice && product.discountPrice < product.price
            ? product.discountPrice
            : product.price];

      return {
        id: product.id,
        slug: product.slug,
        name: product.name,
        image_url: product.imageUrl,
        price_min: Math.min(...prices),
        price_max: Math.max(...prices),
        brand_name: product.brand?.name ?? null,
      };
    });

  return {
    products: productSuggestions,
    categories: categories
      .sort((a, b) => scoreLabel(b.name, q) - scoreLabel(a.name, q))
      .slice(0, 5)
      .map((category) => ({
        slug: category.slug,
        name: category.name,
        count: category._count.products,
      })),
    brands: brands
      .sort((a, b) => scoreLabel(b.name, q) - scoreLabel(a.name, q))
      .slice(0, 5)
      .map((brand) => ({
        slug: brand.slug,
        name: brand.name,
        count: brand._count.products,
      })),
    total: productSuggestions.length,
  };
}

export async function GET(request: NextRequest) {
  try {
    const sp = request.nextUrl.searchParams;
    const q = (sp.get("q") ?? "").trim().slice(0, 100);
    const limit = Math.min(20, Math.max(1, Number(sp.get("limit") ?? 8)));

    if (q.length < 2) return NextResponse.json(EMPTY);

    const [meiliResult, dbResult] = await Promise.all([
      suggestFromMeili(q, limit).catch(() => EMPTY),
      suggestFromDb(q, limit).catch(() => EMPTY),
    ]);

    return NextResponse.json({
      products: mergeUnique(meiliResult.products, dbResult.products, 5),
      categories: mergeUnique(meiliResult.categories, dbResult.categories, 5),
      brands: mergeUnique(meiliResult.brands, dbResult.brands, 5),
      total: Math.max(meiliResult.total, dbResult.total),
    });
  } catch (error) {
    return NextResponse.json(
      {
        ...EMPTY,
        error: error instanceof Error ? error.message : "Suggest failed",
      },
      { status: 200 },
    );
  }
}
