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

/** Filter kategori/brand aktif dari catalog screen — supaya suggestion
 *  konsisten dengan grid produk yang sedang di-filter. id untuk query DB,
 *  slug untuk filter Meili. Null = tidak ada filter (suggestion global). */
type SuggestFilter = {
  categoryId: string | null;
  categorySlug: string | null;
  brandId: string | null;
  brandSlug: string | null;
};

const NO_FILTER: SuggestFilter = {
  categoryId: null,
  categorySlug: null,
  brandId: null,
  brandSlug: null,
};

async function suggestFromMeili(
  q: string,
  limit: number,
  filter: SuggestFilter,
): Promise<SuggestResponse> {
  const filterClauses = ["is_active = true"];
  if (filter.categorySlug) {
    filterClauses.push(`category_slug = "${filter.categorySlug}"`);
  }
  if (filter.brandSlug) {
    filterClauses.push(`brand_slug = "${filter.brandSlug}"`);
  }
  const result = await productIndex.search(q, {
    filter: filterClauses.join(" AND "),
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
  flashSaleEndsAt?: Date | null;
  hasVariants: boolean;
  brand: { name: string } | null;
  variants: Array<{ id?: string; price: number; stock: number }>;
  discountItems?: Array<{
    variantId: string | null;
    discountedPrice: number;
    discount: { endsAt: Date };
  }>;
}): SuggestProduct {
  // Apply Flash Sale + Promo Toko via resolveActiveDiscount (inline).
  // Search suggestion dropdown harus konsisten dengan product card di
  // catalog — kalau Promo Toko aktif, dropdown tampil harga setelah
  // diskon, bukan harga full.
  const now = new Date();
  const items = product.discountItems ?? [];

  let priceMin: number;
  let priceMax: number;

  if (product.hasVariants && product.variants.length > 0) {
    // Per-variant pricing
    const effectivePrices = product.variants.map((v) => {
      const variantPromoItems = items
        .filter((it) => v.id !== undefined && it.variantId === v.id)
        .map((it) => ({
          discountedPrice: it.discountedPrice,
          endsAt: it.discount.endsAt,
        }));
      // Flash Sale ratio
      const flashSale =
        product.flashSaleEndsAt &&
        product.discountPrice &&
        product.price > 0
          ? {
              discountPrice: Math.round(
                v.price * (product.discountPrice / product.price),
              ),
              endsAt: product.flashSaleEndsAt,
            }
          : null;
      const effective = resolveInlineDiscount(
        v.price,
        flashSale,
        variantPromoItems,
        now,
      );
      return effective ?? v.price;
    });
    priceMin = Math.min(...effectivePrices);
    priceMax = Math.max(...product.variants.map((v) => v.price));
  } else {
    // Single product
    const promoItems = items
      .filter((it) => it.variantId === null)
      .map((it) => ({
        discountedPrice: it.discountedPrice,
        endsAt: it.discount.endsAt,
      }));
    const effective = resolveInlineDiscount(
      product.price,
      {
        discountPrice: product.discountPrice,
        endsAt: product.flashSaleEndsAt ?? null,
      },
      promoItems,
      now,
    );
    priceMin = effective ?? product.price;
    priceMax = product.price;
  }

  return {
    id: product.id,
    slug: product.slug,
    name: product.name,
    image_url: product.imageUrl,
    price_min: priceMin,
    price_max: priceMax,
    brand_name: product.brand?.name ?? null,
  };
}

/** Inline pricing utility (sync TypeScript supaya bisa di file ini). */
function resolveInlineDiscount(
  basePrice: number,
  flashSale: { discountPrice: number | null; endsAt: Date | null } | null,
  promoItems: Array<{ discountedPrice: number; endsAt: Date }>,
  now: Date,
): number | null {
  let best: number | null = null;
  if (
    flashSale &&
    flashSale.endsAt &&
    flashSale.endsAt > now &&
    flashSale.discountPrice &&
    flashSale.discountPrice > 0 &&
    flashSale.discountPrice < basePrice
  ) {
    best = flashSale.discountPrice;
  }
  for (const item of promoItems) {
    if (item.endsAt <= now) continue;
    if (item.discountedPrice <= 0) continue;
    if (item.discountedPrice >= basePrice) continue;
    if (best === null || item.discountedPrice < best) {
      best = item.discountedPrice;
    }
  }
  return best;
}

async function hydrateMeiliProductsFromDb(
  meiliProducts: SuggestProduct[],
  filter: SuggestFilter,
): Promise<SuggestProduct[]> {
  const ids = meiliProducts.map((product) => product.id).filter(Boolean);
  if (ids.length === 0) return [];

  const now = new Date();
  const products = await prisma.product.findMany({
    where: {
      id: { in: ids },
      isActive: true,
      OR: suggestableProductState,
      ...(filter.categoryId ? { categoryId: filter.categoryId } : {}),
      ...(filter.brandId ? { brandId: filter.brandId } : {}),
    },
    include: {
      brand: { select: { name: true } },
      variants: {
        where: { deletedAt: null, isActive: true },
        select: { id: true, price: true, stock: true },
      },
      // Active Promo Toko items untuk search suggestion price.
      discountItems: {
        where: {
          isItemActive: true,
          discount: {
            isActive: true,
            startsAt: { lte: now },
            endsAt: { gt: now },
          },
        },
        select: {
          variantId: true,
          discountedPrice: true,
          discount: { select: { endsAt: true } },
        },
      },
    },
  });

  const byId = new Map(products.map((product) => [product.id, productToSuggestion(product)]));
  return ids.map((id) => byId.get(id)).filter((product): product is SuggestProduct => Boolean(product));
}

async function trigramSuggestIds(
  query: string,
  limit: number,
  filter: SuggestFilter,
): Promise<string[]> {
  const q = query.trim().toLowerCase();
  if (q.length < 2) return [];

  // Filter kategori/brand aktif — supaya kandidat suggestion produk match
  // grid yang sedang di-filter. Prisma.empty = no-op kalau filter null.
  const categoryClause = filter.categoryId
    ? Prisma.sql`AND "categoryId" = ${filter.categoryId}`
    : Prisma.empty;
  const brandClause = filter.brandId
    ? Prisma.sql`AND "brandId" = ${filter.brandId}`
    : Prisma.empty;

  const rows = await prisma.$queryRaw<Array<{ id: string }>>(Prisma.sql`
    SELECT id
    FROM "Product"
    WHERE "isActive" = true
      ${categoryClause}
      ${brandClause}
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

async function suggestFromDb(
  q: string,
  limit: number,
  filter: SuggestFilter,
): Promise<SuggestResponse> {
  const tokens = tokensFor(q);
  const labelOr = [
    { name: { contains: q, mode: "insensitive" as const } },
    ...tokens.map((token) => ({ name: { contains: token, mode: "insensitive" as const } })),
  ];

  const candidateIds = await trigramSuggestIds(q, Math.max(limit * 4, 12), filter);

  const now2 = new Date();
  const productsPromise =
    candidateIds.length === 0
      ? null
      : prisma.product.findMany({
          where: {
            id: { in: candidateIds },
            isActive: true,
            OR: suggestableProductState,
            ...(filter.categoryId ? { categoryId: filter.categoryId } : {}),
            ...(filter.brandId ? { brandId: filter.brandId } : {}),
          },
          include: {
            brand: { select: { name: true } },
            variants: {
              where: { deletedAt: null, isActive: true },
              select: { id: true, price: true, stock: true },
            },
            // Active Promo Toko items — apply diskon di suggestion.
            discountItems: {
              where: {
                isItemActive: true,
                discount: {
                  isActive: true,
                  startsAt: { lte: now2 },
                  endsAt: { gt: now2 },
                },
              },
              select: {
                variantId: true,
                discountedPrice: true,
                discount: { select: { endsAt: true } },
              },
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
    // Skip label kategori kalau user SUDAH di kategori tertentu (redundant
    // saran "Kategori: X" saat sudah di X). Sama untuk brand.
    categories: filter.categoryId
      ? []
      : categories
          .sort((a, b) => scoreLabel(b.name, q) - scoreLabel(a.name, q))
          .slice(0, 5)
          .map((category) => ({
            slug: category.slug,
            name: category.name,
            count: category._count.products,
          })),
    brands: filter.brandId
      ? []
      : brands
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

/** Resolve nama-atau-slug kategori/brand jadi canonical id+slug.
 *  Dipakai untuk filter suggestion konsisten dengan grid catalog. */
async function resolveSuggestFilter(
  categoryParam: string,
  brandParam: string,
): Promise<SuggestFilter> {
  if (!categoryParam && !brandParam) return NO_FILTER;

  const [category, brand] = await Promise.all([
    categoryParam
      ? prisma.category.findFirst({
          where: {
            OR: [
              { slug: categoryParam },
              { name: { equals: categoryParam, mode: "insensitive" } },
            ],
          },
          select: { id: true, slug: true },
        })
      : Promise.resolve(null),
    brandParam
      ? prisma.brand.findFirst({
          where: {
            OR: [
              { slug: brandParam },
              { name: { equals: brandParam, mode: "insensitive" } },
            ],
          },
          select: { id: true, slug: true },
        })
      : Promise.resolve(null),
  ]);

  return {
    categoryId: category?.id ?? null,
    categorySlug: category?.slug ?? null,
    brandId: brand?.id ?? null,
    brandSlug: brand?.slug ?? null,
  };
}

export async function GET(request: NextRequest) {
  try {
    const sp = request.nextUrl.searchParams;
    const q = (sp.get("q") ?? "").trim().slice(0, 100);
    const limit = Math.min(20, Math.max(1, Number(sp.get("limit") ?? 8)));

    if (q.length < 2) return NextResponse.json(EMPTY);

    // Filter kategori/brand aktif (dari catalog screen). Terima nama ATAU
    // slug (catalog kirim nama dari home chip / slug dari deep-link).
    // Resolve ke canonical id+slug. Kalau tidak resolve (typo/stale),
    // treat sebagai no-filter (suggestion global) — graceful, tidak
    // bikin suggestion kosong total.
    const categoryParam = (sp.get("category") ?? "").trim().slice(0, 80);
    const brandParam = (sp.get("brand") ?? "").trim().slice(0, 80);
    const filter = await resolveSuggestFilter(categoryParam, brandParam);

    const [meiliResult, dbResult] = await Promise.all([
      isMeiliEnabled()
        ? suggestFromMeili(q, limit, filter).catch(() => EMPTY)
        : Promise.resolve(EMPTY),
      suggestFromDb(q, limit, filter).catch(() => EMPTY),
    ]);
    const hydratedMeiliProducts = await hydrateMeiliProductsFromDb(
      meiliResult.products,
      filter,
    ).catch(() => []);
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
