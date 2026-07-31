/**
 * Service layer Meilisearch — index, sync, query products.
 *
 * Strategy:
 *   - 1 index: "products"
 *   - Searchable: name, brand_name, variant_names, sku_codes
 *   - Filterable: category_slug, brand_slug, price_min, total_stock, avg_rating, is_active
 *   - Sortable: price_min, created_at, avg_rating, review_count
 *   - Synonyms: anjing↔dog, kucing↔cat, pakan↔makanan↔food, dst.
 *
 * Sinkronisasi:
 *   - syncProduct(id): re-index satu produk (panggil setelah create/update/delete)
 *   - reindexAll(): full re-index (untuk initial setup atau recovery)
 */

import { Meilisearch } from "meilisearch";
import { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { discountOnlyWhere } from "@/lib/product-ranking";
import { productIsVisibleWhere } from "@/lib/product/admin-product-form";
import {
  normalizeSearchText,
  tokenizeSearchQuery,
  tokenizedSearchWhere,
} from "@/lib/search-tokens";
import {
  applyProductIndexSettings,
  buildProductSearchText,
  productToSearchDoc as mapProductToSearchDoc,
} from "@/lib/search-document.mjs";

const HOST = process.env.MEILISEARCH_HOST ?? "";
const KEY = process.env.MEILISEARCH_API_KEY ?? "";
const INDEX_NAME = process.env.MEILISEARCH_INDEX ?? "products";

export const meili = new Meilisearch({
  host: HOST || "http://localhost:7700",
  apiKey: KEY,
});
export const productIndex = meili.index(INDEX_NAME);

/**
 * Meilisearch hanya aktif kalau host di-set dan tidak menunjuk ke localhost
 * di environment production (Vercel). Tanpa gate ini, deploy Vercel akan
 * coba connect ke localhost:7700 dan men-spam error log setiap request.
 */
export function isMeiliEnabled() {
  if (!HOST) return false;
  const isVercel = process.env.VERCEL === "1";
  if (isVercel && (HOST.includes("localhost") || HOST.includes("127.0.0.1"))) {
    return false;
  }
  return true;
}

export type ProductSearchDoc = {
  id: string;
  slug: string;
  name: string;
  description: string;
  category_id: string | null;
  category_slug: string | null;
  category_name: string | null;
  brand_id: string | null;
  brand_slug: string | null;
  brand_name: string | null;
  variant_names: string[];
  sku_codes: string[];
  price_min: number;
  price_max: number;
  discount_price: number | null;
  stock: number;
  total_stock: number;
  weight_grams: number;
  avg_rating: number;
  review_count: number;
  created_at: number; // unix seconds
  image_url: string | null;
  is_active: boolean;
  has_variants: boolean;
};

/**
 * Setup index (idempotent). Panggil sekali saat awal atau saat config berubah.
 */
export async function setupSearchIndex() {
  // Pastikan index ada
  try {
    await meili.getIndex(INDEX_NAME);
  } catch {
    await meili.createIndex(INDEX_NAME, { primaryKey: "id" });
  }

  await applyProductIndexSettings(productIndex);
}

/**
 * Build dokumen searchable untuk satu produk (gabungkan variants, brand, category).
 */
export async function buildProductDoc(productId: string): Promise<ProductSearchDoc | null> {
  const p = await prisma.product.findUnique({
    where: { id: productId },
    include: {
      category: { select: { id: true, name: true, slug: true } },
      brand: { select: { id: true, name: true, slug: true } },
      variants: {
        where: { deletedAt: null, isActive: true },
        include: {
          options: {
            include: { option: { select: { value: true } } },
          },
        },
      },
    },
  });
  if (!p) return null;

  return mapProductToSearchDoc(p);
}

/**
 * Sync satu produk ke search index.
 * Panggil setelah create/update product, atau setelah variant berubah.
 *
 * Selalu update kolom Product.searchText di DB (dipakai DB-fallback search
 * dengan trigram). Push ke Meilisearch hanya kalau isMeiliEnabled().
 */
export async function syncProduct(productId: string) {
  try {
    const product = await prisma.product.findUnique({
      where: { id: productId },
      include: {
        category: { select: { id: true, name: true, slug: true } },
        brand: { select: { id: true, name: true, slug: true } },
        variants: {
          where: { deletedAt: null, isActive: true },
          include: {
            options: {
              include: { option: { select: { value: true } } },
            },
          },
        },
      },
    });

    if (!product) {
      if (isMeiliEnabled()) {
        await productIndex.deleteDocument(productId).catch(() => {});
      }
      return { synced: false, deleted: true };
    }

    const searchText = buildProductSearchText(product);
    // Raw SQL supaya tidak bergantung pada Prisma client yang sudah include
    // field searchText. Build di Vercel akan tetap regenerate, tapi runtime
    // tidak butuh typed field untuk update sederhana ini.
    await prisma.$executeRaw(
      Prisma.sql`UPDATE "Product" SET "searchText" = ${searchText} WHERE id = ${productId}`,
    );

    if (isMeiliEnabled()) {
      if (product.isActive) {
        const doc = mapProductToSearchDoc(product);
        await productIndex.addDocuments([doc]);
      } else {
        // Produk non-aktif → HAPUS dari index, bukan push ulang. Tanpa
        // ini, produk yang di-hide admin tetap "nyangkut" di index
        // (walau query selalu filter is_active=true, jadi tidak muncul
        // ke pembeli — ini defense-in-depth + index bersih). Catatan:
        // saat ini Meili tidak aktif (isMeiliEnabled=false), jadi branch
        // ini no-op; benar otomatis kalau Meili nanti diaktifkan.
        await productIndex.deleteDocument(productId).catch(() => {});
      }
    }

    return { synced: true, deleted: !product.isActive };
  } catch (e) {
    console.error("[search.syncProduct] failed:", e);
    return { synced: false, deleted: false, error: String(e) };
  }
}

function escapeMeiliFilterValue(value: string) {
  return value.replace(/"/g, '\\"');
}

function multiValueMeiliFilter(field: string, values: string[]) {
  if (values.length === 0) return null;
  return `(${values.map((value) => `${field} = "${escapeMeiliFilterValue(value)}"`).join(" OR ")})`;
}

function meiliSortFor(sort: SearchSort) {
  if (sort === "price_asc") return ["price_min:asc"];
  if (sort === "price_desc") return ["price_min:desc"];
  if (sort === "newest") return ["created_at:desc"];
  if (sort === "rating_desc") return ["avg_rating:desc", "review_count:desc"];
  if (sort === "best_seller") return ["review_count:desc", "avg_rating:desc"];
  return undefined;
}

export function buildMeiliSearchParams(opts: NormalizedSearchOptions) {
  const limit = Math.max(1, Math.min(60, opts.perPage));
  const page = Math.max(1, opts.page);
  const offset = Math.max(0, (page - 1) * limit);
  const filters: string[] = ["is_active = true"];

  const categoryFilter = multiValueMeiliFilter("category_slug", opts.categorySlug);
  if (categoryFilter) filters.push(categoryFilter);

  const brandFilter = multiValueMeiliFilter("brand_slug", opts.brandSlug);
  if (brandFilter) filters.push(brandFilter);

  if (opts.minPrice !== undefined && Number.isFinite(opts.minPrice)) {
    filters.push(`price_min >= ${Math.max(0, opts.minPrice)}`);
  }
  if (opts.maxPrice !== undefined && Number.isFinite(opts.maxPrice)) {
    filters.push(`price_min <= ${Math.max(0, opts.maxPrice)}`);
  }
  if (opts.inStock) filters.push("total_stock > 0");
  if (opts.minRating !== undefined && Number.isFinite(opts.minRating)) {
    filters.push(`avg_rating >= ${opts.minRating}`);
  }

  return {
    q: opts.q,
    filter: filters.join(" AND "),
    limit,
    offset,
    candidateLimit: Math.min(1000, Math.max(offset + limit * 8, limit * 10)),
    sort: meiliSortFor(opts.sort),
  };
}

function rangeFilter(min?: number, max?: number): Prisma.IntFilter | undefined {
  if (min === undefined && max === undefined) return undefined;
  return {
    ...(min !== undefined && Number.isFinite(min) ? { gte: Math.max(0, min) } : {}),
    ...(max !== undefined && Number.isFinite(max) ? { lte: Math.max(0, max) } : {}),
  };
}

function productPriceWhere(opts: NormalizedSearchOptions): Prisma.ProductWhereInput | undefined {
  const priceRange = rangeFilter(opts.minPrice, opts.maxPrice);
  if (!priceRange) return undefined;

  return {
    OR: [
      { hasVariants: false, price: priceRange },
      { hasVariants: false, discountPrice: priceRange },
      {
        hasVariants: true,
        variants: {
          some: {
            deletedAt: null,
            isActive: true,
            price: priceRange,
          },
        },
      },
    ],
  };
}

export function productSearchWhere(query: string): Prisma.ProductWhereInput | undefined {
  // Dibangun lewat tokenizedSearchWhere supaya SATU aturan tokenisasi
  // berlaku di seluruh app — termasuk fallback query mentah saat query
  // terlalu pendek untuk jadi token (mis. "5"). Tanpa fallback itu,
  // pencarian 1 karakter mengembalikan undefined = TANPA filter, sehingga
  // katalog/daftar admin tampil utuh dan terlihat seperti filter rusak.
  return tokenizedSearchWhere<Prisma.ProductWhereInput>(query, (token) => [
    { name: { contains: token, mode: "insensitive" as const } },
    { brand: { name: { contains: token, mode: "insensitive" as const } } },
    { variants: { some: { sku: { contains: token, mode: "insensitive" as const } } } },
    {
      variants: {
        some: {
          options: {
            some: {
              option: {
                value: { contains: token, mode: "insensitive" as const },
              },
            },
          },
        },
      },
    },
  ]);
}

export function buildDbProductWhere(opts: NormalizedSearchOptions) {
  const andFilters: Prisma.ProductWhereInput[] = [];
  const searchWhere = productSearchWhere(opts.q);
  if (searchWhere) andFilters.push(searchWhere);

  const priceWhere = productPriceWhere(opts);
  if (priceWhere) andFilters.push(priceWhere);

  if (opts.inStock) {
    andFilters.push({
      OR: [
        { hasVariants: false, stock: { gt: 0 } },
        {
          hasVariants: true,
          variants: { some: { deletedAt: null, isActive: true, stock: { gt: 0 } } },
        },
      ],
    });
  }

  if (opts.minRating !== undefined && Number.isFinite(opts.minRating)) {
    andFilters.push({ avgRating: { gte: opts.minRating } });
  }

  return {
    isActive: true,
    ...(opts.categorySlug.length > 0 ? { category: { slug: { in: opts.categorySlug } } } : {}),
    ...(opts.brandSlug.length > 0 ? { brand: { slug: { in: opts.brandSlug } } } : {}),
    ...(andFilters.length > 0 ? { AND: andFilters } : {}),
  };
}

export function buildDbSearchPageArgs(opts: NormalizedSearchOptions) {
  const limit = Math.max(1, Math.min(60, opts.perPage));
  const page = Math.max(1, opts.page);
  const orderBy =
    opts.sort === "price_asc"
      ? [{ price: "asc" as const }, { name: "asc" as const }]
      : opts.sort === "price_desc"
        ? [{ price: "desc" as const }, { name: "asc" as const }]
        : opts.sort === "newest"
          ? [{ createdAt: "desc" as const }]
          : opts.sort === "rating_desc"
            ? [{ avgRating: "desc" as const }, { reviewCount: "desc" as const }]
            : opts.sort === "best_seller"
              ? [{ reviewCount: "desc" as const }, { avgRating: "desc" as const }]
              : [{ createdAt: "desc" as const }];

  return {
    where: buildDbProductWhere(opts),
    orderBy,
    skip: Math.max(0, (page - 1) * limit),
    take: limit,
  };
}

async function hydrateProductDocsById(productIds: string[]) {
  const ids = Array.from(new Set(productIds.filter(Boolean)));
  if (ids.length === 0) return [];

  const products = await prisma.product.findMany({
    where: { id: { in: ids }, isActive: true },
    include: getProductSearchInclude(),
  });
  const byId = new Map(
    products.map((product) => [
      product.id,
      mapProductToSearchDoc(product as ProductForSearchDoc),
    ]),
  );

  return ids.map((id) => byId.get(id)).filter((doc): doc is ProductSearchDoc => Boolean(doc));
}

export async function syncProductsToSearchIndex(productIds: string[], concurrency = 5) {
  const pending = Array.from(new Set(productIds.filter(Boolean)));
  const summary = {
    requested: pending.length,
    synced: 0,
    deleted: 0,
    failed: 0,
    errors: [] as Array<{ productId: string; error: string }>,
  };

  if (pending.length === 0) return summary;

  const workerCount = Math.max(1, Math.min(concurrency, pending.length));
  let cursor = 0;

  async function worker() {
    while (cursor < pending.length) {
      const productId = pending[cursor++];
      const result = await syncProduct(productId);

      if (result.synced) {
        summary.synced++;
        continue;
      }
      if (result.deleted) {
        summary.deleted++;
        continue;
      }

      summary.failed++;
      if ("error" in result && result.error) {
        summary.errors.push({ productId, error: result.error });
      }
    }
  }

  await Promise.all(Array.from({ length: workerCount }, () => worker()));
  return summary;
}

/**
 * Hapus produk dari Meilisearch index. Caller sudah menghapus row DB,
 * jadi tidak perlu update searchText.
 */
export async function deleteProductFromIndex(productId: string) {
  if (!isMeiliEnabled()) return;
  try {
    await productIndex.deleteDocument(productId);
  } catch (e) {
    console.error("[search.deleteProductFromIndex] failed:", e);
  }
}

// ── Search query types ─────────────────────────────────────────

export type SearchSort =
  | "relevance"
  | "price_asc"
  | "price_desc"
  | "newest"
  | "rating_desc"
  | "best_seller";

export interface SearchOptions {
  q?: string;
  categorySlug?: string[];
  brandSlug?: string[];
  minPrice?: number;
  maxPrice?: number;
  inStock?: boolean;
  minRating?: number;
  discountOnly?: boolean;
  sort?: SearchSort;
  page?: number;
  perPage?: number;
}

export type SearchFacets = {
  categories: Array<{ slug: string; name: string; count: number }>;
  brands: Array<{ slug: string; name: string; count: number }>;
  price_range: { min: number; max: number };
  weights: Array<{ label: string; min: number; max: number; count: number }>;
};

export type NormalizedSearchOptions = Required<
  Pick<SearchOptions, "q" | "categorySlug" | "brandSlug" | "sort" | "page" | "perPage">
> &
  Pick<SearchOptions, "minPrice" | "maxPrice" | "inStock" | "minRating" | "discountOnly">;

type ProductForSearchDoc = NonNullable<Awaited<ReturnType<typeof prisma.product.findFirst>>> & {
  category: { id: string; name: string; slug: string } | null;
  brand: { id: string; name: string; slug: string } | null;
  variants: Array<{
    sku: string | null;
    price: number;
    stock: number;
    deletedAt: Date | null;
    isActive: boolean;
    options: Array<{ option: { value: string } | null }>;
  }>;
};

// Tidak `as const` lagi karena include sekarang punya nilai dinamis
// (`new Date()` di discountItems where filter). Wrap di function getter
// supaya fresh per call — same pattern dengan getProductListInclude().
function getProductSearchInclude() {
  const now = new Date();
  return {
    category: { select: { id: true, name: true, slug: true } },
    brand: { select: { id: true, name: true, slug: true } },
    variants: {
      where: { deletedAt: null, isActive: true },
      include: {
        options: {
          include: { option: { select: { value: true } } },
        },
      },
    },
    // Active Promo Toko items untuk apply diskon di search results.
    // Match pattern lib/products.ts → searchProductsFromDb akan return
    // discount_price yang konsisten dengan product card di catalog.
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
  };
}

function levenshtein(a: string, b: string) {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;

  const previous = Array.from({ length: b.length + 1 }, (_, index) => index);
  const current = new Array<number>(b.length + 1);

  for (let i = 1; i <= a.length; i++) {
    current[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      current[j] = Math.min(
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + cost,
      );
    }
    for (let j = 0; j <= b.length; j++) previous[j] = current[j];
  }

  return previous[b.length];
}

function tokenMatchesWord(token: string, word: string) {
  if (word.includes(token) || token.includes(word)) return true;
  if (token.length < 3 || word.length < 3) return false;

  const maxDistance = token.length <= 5 ? 1 : 2;
  return (
    Math.abs(word.length - token.length) <= maxDistance &&
    levenshtein(token, word) <= maxDistance
  );
}

function searchFields(item: ProductSearchDoc) {
  return [
    item.name,
    item.brand_name,
    ...item.variant_names,
    ...item.sku_codes,
  ].filter((value): value is string => Boolean(value));
}

function matchesSearchQuery(item: ProductSearchDoc, query: string) {
  const tokens = tokenizeSearchQuery(query);
  if (tokens.length === 0) return true;

  const normalizedFields = searchFields(item).map(normalizeSearchText);
  const haystack = normalizedFields.join(" ");
  const words = haystack.split(/\s+/).filter(Boolean);

  return tokens.every(
    (token) =>
      haystack.includes(token) ||
      words.some((word) => tokenMatchesWord(token, word)),
  );
}

function relevanceScore(item: ProductSearchDoc, query: string) {
  const normalizedQuery = normalizeSearchText(query);
  const tokens = tokenizeSearchQuery(query);
  if (!normalizedQuery || tokens.length === 0) return 0;

  const name = normalizeSearchText(item.name);
  const brand = normalizeSearchText(item.brand_name ?? "");
  const fields = searchFields(item).map(normalizeSearchText).join(" ");

  let score = 0;
  if (name === normalizedQuery) score += 120;
  if (name.startsWith(normalizedQuery)) score += 90;
  if (name.includes(normalizedQuery)) score += 70;
  if (brand === normalizedQuery) score += 80;
  if (brand.includes(normalizedQuery)) score += 55;

  for (const token of tokens) {
    if (name.includes(token)) score += 18;
    else if (brand.includes(token)) score += 14;
    else if (fields.includes(token)) score += 4;
  }

  return score;
}

function buildSearchFacets(items: ProductSearchDoc[]): SearchFacets {
  const categoryMap = new Map<string, { slug: string; name: string; count: number }>();
  const brandMap = new Map<string, { slug: string; name: string; count: number }>();
  const priceMins: number[] = [];
  const priceMaxes: number[] = [];

  for (const item of items) {
    if (item.category_slug && item.category_name) {
      const prev = categoryMap.get(item.category_slug);
      categoryMap.set(item.category_slug, {
        slug: item.category_slug,
        name: item.category_name,
        count: (prev?.count ?? 0) + 1,
      });
    }

    if (item.brand_slug && item.brand_name) {
      const prev = brandMap.get(item.brand_slug);
      brandMap.set(item.brand_slug, {
        slug: item.brand_slug,
        name: item.brand_name,
        count: (prev?.count ?? 0) + 1,
      });
    }

    priceMins.push(item.price_min);
    priceMaxes.push(item.price_max);
  }

  const weightCount = (predicate: (weight: number) => boolean) =>
    items.filter((item) => predicate(item.weight_grams)).length;

  return {
    categories: Array.from(categoryMap.values()).sort((a, b) => b.count - a.count),
    brands: Array.from(brandMap.values()).sort((a, b) => b.count - a.count),
    price_range: {
      min: priceMins.length ? Math.min(...priceMins) : 0,
      max: priceMaxes.length ? Math.max(...priceMaxes) : 0,
    },
    weights: [
      { label: "< 1 KG", min: 0, max: 999, count: weightCount((weight) => weight < 1000) },
      {
        label: "1 - 5 KG",
        min: 1000,
        max: 5000,
        count: weightCount((weight) => weight >= 1000 && weight <= 5000),
      },
      { label: "> 5 KG", min: 5001, max: 999999, count: weightCount((weight) => weight > 5000) },
    ],
  };
}

function filterSearchDocs(items: ProductSearchDoc[], opts: NormalizedSearchOptions) {
  const q = opts.q.trim();
  let filtered = items.filter((item) => item.is_active);

  if (opts.categorySlug.length > 0) {
    filtered = filtered.filter(
      (item) => item.category_slug !== null && opts.categorySlug.includes(item.category_slug),
    );
  }
  if (opts.brandSlug.length > 0) {
    filtered = filtered.filter(
      (item) => item.brand_slug !== null && opts.brandSlug.includes(item.brand_slug),
    );
  }
  if (q) {
    filtered = filtered.filter((item) => matchesSearchQuery(item, q));
  }
  if (opts.minPrice !== undefined && Number.isFinite(opts.minPrice)) {
    filtered = filtered.filter((item) => item.price_min >= Math.max(0, opts.minPrice!));
  }
  if (opts.maxPrice !== undefined && Number.isFinite(opts.maxPrice)) {
    filtered = filtered.filter((item) => item.price_min <= Math.max(0, opts.maxPrice!));
  }
  if (opts.inStock) {
    filtered = filtered.filter((item) => item.total_stock > 0);
  }
  if (opts.minRating !== undefined && Number.isFinite(opts.minRating)) {
    filtered = filtered.filter((item) => item.avg_rating >= opts.minRating!);
  }

  return filtered;
}

function compareSearchItems(sort: SearchSort, query: string) {
  return (a: ProductSearchDoc, b: ProductSearchDoc) => {
    if (sort === "price_asc") return a.price_min - b.price_min || a.name.localeCompare(b.name);
    if (sort === "price_desc") return b.price_min - a.price_min || a.name.localeCompare(b.name);
    if (sort === "newest") return b.created_at - a.created_at || a.name.localeCompare(b.name);
    if (sort === "rating_desc") {
      return (
        b.avg_rating - a.avg_rating ||
        b.review_count - a.review_count ||
        a.name.localeCompare(b.name)
      );
    }
    if (sort === "best_seller") {
      return b.review_count - a.review_count || b.avg_rating - a.avg_rating || a.name.localeCompare(b.name);
    }

    return (
      relevanceScore(b, query) - relevanceScore(a, query) ||
      b.created_at - a.created_at ||
      a.name.localeCompare(b.name)
    );
  };
}

export function filterSortPaginateSearchDocs(
  docs: ProductSearchDoc[],
  opts: NormalizedSearchOptions,
) {
  const q = opts.q.trim();
  let items = filterSearchDocs(docs, opts);
  items = [...items].sort(compareSearchItems(opts.sort, q));

  const total = items.length;
  const facets = buildSearchFacets(items);
  const limit = Math.max(1, Math.min(60, opts.perPage));
  const page = Math.max(1, opts.page);
  const offset = Math.max(0, (page - 1) * limit);

  return {
    items: items.slice(offset, offset + limit),
    total,
    page,
    per_page: limit,
    facets,
  };
}

async function searchProductsFromMeili(opts: NormalizedSearchOptions) {
  const start = Date.now();
  const params = buildMeiliSearchParams(opts);
  const result = await productIndex.search(params.q, {
    filter: params.filter,
    limit: params.candidateLimit,
    offset: 0,
    attributesToRetrieve: ["id"],
    attributesToSearchOn: ["name", "brand_name", "variant_names", "sku_codes"],
    matchingStrategy: "all",
    facets: ["category_slug", "brand_slug", "price_min", "weight_grams"],
    ...(params.sort ? { sort: params.sort } : {}),
  });

  const hits = result.hits as Array<{ id?: string }>;
  const candidateIds = hits.map((hit) => hit.id).filter((id): id is string => Boolean(id));
  const filteredDocs = filterSearchDocs(await hydrateProductDocsById(candidateIds), opts);
  const hydratedDocs = filteredDocs.slice(params.offset, params.offset + params.limit);
  const facets = buildSearchFacets(filteredDocs);

  return {
    items: hydratedDocs,
    total: filteredDocs.length,
    page: Math.max(1, opts.page),
    per_page: params.limit,
    facets,
    took_ms: Date.now() - start,
    source: "meilisearch" as const,
  };
}

/**
 * Cari kandidat product IDs via pg_trgm similarity + ILIKE.
 * Pakai GIN trigram index di Product.searchText. Return urut by similarity.
 */
async function trigramCandidateIds(query: string, limit = 500): Promise<string[]> {
  const q = query.trim().toLowerCase();
  if (!q) return [];

  const rows = await prisma.$queryRaw<Array<{ id: string }>>(Prisma.sql`
    SELECT id
    FROM "Product"
    WHERE "isActive" = true
      AND (
        "searchText" ILIKE ${"%" + q + "%"}
        OR "searchText" % ${q}
        OR similarity("searchText", ${q}) > 0.15
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

async function searchProductsFromDb(opts: NormalizedSearchOptions) {
  const start = Date.now();
  const q = opts.q.trim();

  let candidateIds: string[] | undefined;
  if (q.length >= 2) {
    candidateIds = await trigramCandidateIds(q, 500);
    if (candidateIds.length === 0) {
      return {
        items: [],
        total: 0,
        page: Math.max(1, opts.page),
        per_page: Math.max(1, Math.min(60, opts.perPage)),
        facets: buildSearchFacets([]),
        took_ms: Date.now() - start,
        source: "database" as const,
      };
    }
  }

  const where: Prisma.ProductWhereInput = {
    isActive: true,
    // Produk yang masih setengah jadi (creationState "creating") TIDAK boleh
    // bocor ke pelanggan. /api/products sudah pakai guard ini; search belum,
    // jadi produk stuck bisa muncul di /search. Samakan.
    ...productIsVisibleWhere(),
    ...(candidateIds ? { id: { in: candidateIds } } : {}),
    ...(opts.categorySlug.length > 0 ? { category: { slug: { in: opts.categorySlug } } } : {}),
    ...(opts.brandSlug.length > 0 ? { brand: { slug: { in: opts.brandSlug } } } : {}),
  };

  const priceWhere = productPriceWhere(opts);
  const stockWhere: Prisma.ProductWhereInput | undefined = opts.inStock
    ? {
        OR: [
          { hasVariants: false, stock: { gt: 0 } },
          {
            hasVariants: true,
            variants: { some: { deletedAt: null, isActive: true, stock: { gt: 0 } } },
          },
        ],
      }
    : undefined;
  const ratingWhere: Prisma.ProductWhereInput | undefined =
    opts.minRating !== undefined && Number.isFinite(opts.minRating)
      ? { avgRating: { gte: opts.minRating } }
      : undefined;

  const discountWhere: Prisma.ProductWhereInput | undefined = opts.discountOnly
    ? discountOnlyWhere()
    : undefined;

  const andFilters = [priceWhere, stockWhere, ratingWhere, discountWhere].filter(
    (f): f is Prisma.ProductWhereInput => Boolean(f),
  );
  if (andFilters.length > 0) where.AND = andFilters;

  // NOTE: tanpa orderBy, `take: 2000` mengambil 2000 baris ARBITRER — begitu
  // katalog lewat 2000 produk, hasilnya jadi non-deterministik. Beri urutan
  // tetap (terbaru dulu) supaya potongannya stabil & bisa dijelaskan.
  const products = await prisma.product.findMany({
    where,
    include: getProductSearchInclude(),
    orderBy: [{ createdAt: "desc" }, { id: "asc" }],
    take: candidateIds ? undefined : 2000,
  });

  const allDocs = products.map((product) =>
    mapProductToSearchDoc(product as ProductForSearchDoc),
  );
  // `where` di atas sudah menyaring kasar; di sini disamakan persis dengan
  // badge diskon di kartu produk (butuh harga efektif yang benar-benar turun).
  const docs = opts.discountOnly
    ? allDocs.filter(
        (doc) => doc.discount_price !== null && doc.discount_price < doc.price_min,
      )
    : allDocs;

  // Kalau ada candidateIds, sort sesuai urutan kandidat (sudah by similarity).
  // Kalau opts.sort bukan "relevance", override dengan compareSearchItems.
  let items: ProductSearchDoc[];
  if (candidateIds && opts.sort === "relevance") {
    const orderMap = new Map(candidateIds.map((id, i) => [id, i]));
    items = [...docs].sort(
      (a, b) => (orderMap.get(a.id) ?? Infinity) - (orderMap.get(b.id) ?? Infinity),
    );
  } else {
    items = [...docs].sort(compareSearchItems(opts.sort, q));
  }

  const total = items.length;
  const facets = buildSearchFacets(items);
  const limit = Math.max(1, Math.min(60, opts.perPage));
  const page = Math.max(1, opts.page);
  const offset = Math.max(0, (page - 1) * limit);

  return {
    items: items.slice(offset, offset + limit),
    total,
    page,
    per_page: limit,
    facets,
    took_ms: Date.now() - start,
    source: "database" as const,
  };
}

/**
 * Eksekusi search dengan filter + sort + paginasi.
 * Return shape mirip API response.
 */
export async function searchProducts(opts: SearchOptions) {
  const {
    q = "",
    categorySlug = [],
    brandSlug = [],
    minPrice,
    maxPrice,
    inStock,
    minRating,
    discountOnly,
    sort = "relevance",
    page = 1,
    perPage = 24,
  } = opts;

  const limit = Math.max(1, Math.min(60, perPage));
  const normalized = {
    q,
    categorySlug,
    brandSlug,
    minPrice,
    maxPrice,
    inStock,
    minRating,
    discountOnly,
    sort,
    page,
    perPage: limit,
  };

  if (isMeiliEnabled()) {
    try {
      return await searchProductsFromMeili(normalized);
    } catch (error) {
      console.error("[searchProducts] Meilisearch failed, using database fallback:", error);
    }
  }
  return searchProductsFromDb(normalized);
}
