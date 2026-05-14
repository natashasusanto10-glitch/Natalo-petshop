/**
 * GET /api/search/suggest?q=...&limit=8
 *
 * Auto-suggest untuk dropdown search. Meilisearch dipakai sebagai sumber
 * kandidat/ranking bila tersedia, tetapi data final produk selalu di-hydrate
 * ulang dari database agar harga, stok, status aktif, dan varian tetap fresh.
 */
import { NextRequest, NextResponse } from "next/server";
import { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { isMeiliEnabled, productIndex } from "@/lib/search";
import {
  EMPTY_SUGGEST_RESPONSE as EMPTY,
  mergeSuggestionProducts,
  type SuggestProduct,
  type SuggestResponse,
} from "@/lib/search-suggest";

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

function tokenWhere(token: string) {
  return [
    { name: { contains: token, mode: "insensitive" as const } },
    { description: { contains: token, mode: "insensitive" as const } },
    { category: { name: { contains: token, mode: "insensitive" as const } } },
    { brand: { name: { contains: token, mode: "insensitive" as const } } },
    { variants: { some: { sku: { contains: token, mode: "insensitive" as const } } } },
  ];
}

const suggestableProductState = [
  { hasVariants: false },
  { variants: { some: { deletedAt: null, isActive: true } } },
];

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

function productToSuggestion(product: {
  id: string;
  slug: string;
  name: string;
  imageUrl: string | null;
  price: number;
  discountPrice: number | null;
  hasVariants: boolean;
  brand: { name: string } | null;
  variants: Array<{ price: number; stock: number }>;
}): SuggestProduct {
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
}

async function hydrateMeiliProductsFromDb(
  meiliProducts: SuggestProduct[],
): Promise<SuggestProduct[]> {
  const ids = meiliProducts.map((product) => product.id).filter(Boolean);
  if (ids.length === 0) return [];

  const products = await prisma.product.findMany({
    where: {
      id: { in: ids },
      isActive: true,
      OR: suggestableProductState,
    },
    include: {
      brand: { select: { name: true } },
      variants: {
        where: { deletedAt: null, isActive: true },
        select: { price: true, stock: true },
      },
    },
  });

  const byId = new Map(products.map((product) => [product.id, productToSuggestion(product)]));
  return ids.map((id) => byId.get(id)).filter((product): product is SuggestProduct => Boolean(product));
}

async function trigramSuggestIds(query: string, limit: number): Promise<string[]> {
  const q = query.trim().toLowerCase();
  if (q.length < 2) return [];

  const rows = await prisma.$queryRaw<Array<{ id: string }>>(Prisma.sql`
    SELECT id
    FROM "Product"
    WHERE "isActive" = true
      AND (
        "searchText" ILIKE ${"%" + q + "%"}
        OR "searchText" % ${q}
        OR similarity("searchText", ${q}) > 0.2
      )
    ORDER BY
      CASE WHEN lower("name") = ${q} THEN 0
           WHEN "searchText" ILIKE ${q + "%"} THEN 1
           WHEN "searchText" ILIKE ${"%" + q + "%"} THEN 2
           ELSE 3
      END,
      similarity("searchText", ${q}) DESC,
      "createdAt" DESC
    LIMIT ${limit}
  `);

  return rows.map((row) => row.id);
}

async function suggestFromDb(q: string, limit: number): Promise<SuggestResponse> {
  const tokens = tokensFor(q);
  const labelOr = [
    { name: { contains: q, mode: "insensitive" as const } },
    ...tokens.map((token) => ({ name: { contains: token, mode: "insensitive" as const } })),
  ];

  const candidateIds = await trigramSuggestIds(q, Math.max(limit * 4, 12));

  const productsPromise =
    candidateIds.length === 0
      ? null
      : prisma.product.findMany({
          where: {
            id: { in: candidateIds },
            isActive: true,
            OR: suggestableProductState,
          },
          include: {
            brand: { select: { name: true } },
            variants: {
              where: { deletedAt: null, isActive: true },
              select: { price: true, stock: true },
            },
          },
        });

  const [products, categories, brands] = await Promise.all([
    productsPromise ?? Promise.resolve([]),
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

  // Sort produk sesuai urutan kandidat dari trigram (already ranked by similarity).
  const orderMap = new Map(candidateIds.map((id, i) => [id, i]));
  const productSuggestions = [...products]
    .sort((a, b) => (orderMap.get(a.id) ?? Infinity) - (orderMap.get(b.id) ?? Infinity))
    .slice(0, 5)
    .map(productToSuggestion);

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
      isMeiliEnabled() ? suggestFromMeili(q, limit).catch(() => EMPTY) : Promise.resolve(EMPTY),
      suggestFromDb(q, limit).catch(() => EMPTY),
    ]);
    const hydratedMeiliProducts = await hydrateMeiliProductsFromDb(meiliResult.products).catch(
      () => [],
    );
    const products = mergeSuggestionProducts({
      dbProducts: dbResult.products,
      meiliProducts: hydratedMeiliProducts,
      limit: 5,
    });

    return NextResponse.json({
      products,
      categories: dbResult.categories,
      brands: dbResult.brands,
      total: Math.max(dbResult.total, products.length),
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
