/**
 * Service layer Meilisearch — index, sync, query products.
 *
 * Strategy:
 *   - 1 index: "products"
 *   - Searchable: name, brand_name, category_name, variant_names, sku_codes, description
 *   - Filterable: category_slug, brand_slug, price_min, total_stock, avg_rating, is_active
 *   - Sortable: price_min, created_at, avg_rating, review_count
 *   - Synonyms: anjing↔dog, kucing↔cat, pakan↔makanan↔food, dst.
 *
 * Sinkronisasi:
 *   - syncProduct(id): re-index satu produk (panggil setelah create/update/delete)
 *   - reindexAll(): full re-index (untuk initial setup atau recovery)
 */

import { Meilisearch } from "meilisearch";
import { prisma } from "@/lib/prisma";

const HOST = process.env.MEILISEARCH_HOST ?? "http://localhost:7700";
const KEY = process.env.MEILISEARCH_API_KEY ?? "";
const INDEX_NAME = process.env.MEILISEARCH_INDEX ?? "products";

export const meili = new Meilisearch({ host: HOST, apiKey: KEY });
export const productIndex = meili.index(INDEX_NAME);

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

const SYNONYMS: Record<string, string[]> = {
  anjing: ["dog"],
  dog: ["anjing"],
  kucing: ["cat"],
  cat: ["kucing"],
  ikan: ["fish"],
  fish: ["ikan"],
  pakan: ["makanan", "food"],
  makanan: ["pakan", "food"],
  food: ["makanan", "pakan"],
  vitamin: ["suplemen"],
  suplemen: ["vitamin"],
  "obat kutu": ["fleatick", "anti kutu"],
  fleatick: ["obat kutu", "anti kutu"],
  "anti kutu": ["obat kutu", "fleatick"],
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

  await productIndex.updateSearchableAttributes([
    "name",          // weight tertinggi (pertama)
    "brand_name",
    "category_name",
    "variant_names",
    "sku_codes",
    "description",   // weight terendah
  ]);

  await productIndex.updateFilterableAttributes([
    "category_id",
    "category_slug",
    "brand_id",
    "brand_slug",
    "price_min",
    "price_max",
    "total_stock",
    "weight_grams",
    "avg_rating",
    "review_count",
    "is_active",
  ]);

  await productIndex.updateSortableAttributes([
    "price_min",
    "created_at",
    "avg_rating",
    "review_count",
  ]);

  await productIndex.updateSynonyms(SYNONYMS);

  await productIndex.updateTypoTolerance({
    enabled: true,
    minWordSizeForTypos: { oneTypo: 4, twoTypos: 8 },
  });
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

  // Hitung price_min/max & total_stock dari varian aktif (kalau ada)
  let priceMin = p.price;
  let priceMax = p.price;
  let totalStock = p.stock;

  if (p.hasVariants && p.variants.length > 0) {
    const prices = p.variants.map((v) => v.price);
    priceMin = Math.min(...prices);
    priceMax = Math.max(...prices);
    totalStock = p.variants.reduce((s, v) => s + v.stock, 0);
  }

  // Variant names (deduplicated)
  const variantNames = Array.from(
    new Set(
      p.variants
        .flatMap((v) => v.options.map((vo) => vo.option?.value))
        .filter((x): x is string => Boolean(x))
    )
  );

  const skuCodes = p.variants
    .map((v) => v.sku)
    .filter((s): s is string => Boolean(s));

  return {
    id: p.id,
    slug: p.slug,
    name: p.name,
    description: p.description ?? "",
    category_id: p.categoryId,
    category_slug: p.category?.slug ?? null,
    category_name: p.category?.name ?? null,
    brand_id: p.brandId,
    brand_slug: p.brand?.slug ?? null,
    brand_name: p.brand?.name ?? null,
    variant_names: variantNames,
    sku_codes: skuCodes,
    price_min: priceMin,
    price_max: priceMax,
    discount_price: p.discountPrice,
    stock: p.stock,
    total_stock: totalStock,
    weight_grams: p.weightGram,
    avg_rating: p.avgRating,
    review_count: p.reviewCount,
    created_at: Math.floor(p.createdAt.getTime() / 1000),
    image_url: p.imageUrl,
    is_active: p.isActive,
    has_variants: p.hasVariants,
  };
}

/**
 * Sync satu produk ke search index.
 * Panggil setelah create/update product, atau setelah variant berubah.
 */
export async function syncProduct(productId: string) {
  try {
    const doc = await buildProductDoc(productId);
    if (!doc) {
      // Produk dihapus → hapus dari index
      await productIndex.deleteDocument(productId);
      return { synced: false, deleted: true };
    }
    await productIndex.addDocuments([doc]);
    return { synced: true, deleted: false };
  } catch (e) {
    // Jangan throw — search-index gagal tidak boleh block CRUD utama
    console.error("[search.syncProduct] failed:", e);
    return { synced: false, deleted: false, error: String(e) };
  }
}

/**
 * Hapus produk dari index (untuk delete event).
 */
export async function deleteProductFromIndex(productId: string) {
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
  sort?: SearchSort;
  page?: number;
  perPage?: number;
}

const SORT_MAP: Record<SearchSort, string[] | undefined> = {
  relevance: undefined,
  price_asc: ["price_min:asc"],
  price_desc: ["price_min:desc"],
  newest: ["created_at:desc"],
  rating_desc: ["avg_rating:desc", "review_count:desc"],
  best_seller: ["review_count:desc"],
};

type ProductForSearchDoc = NonNullable<Awaited<ReturnType<typeof prisma.product.findFirst>>> & {
  category: { id: string; name: string; slug: string } | null;
  brand: { id: string; name: string; slug: string } | null;
  variants: Array<{
    sku: string | null;
    price: number;
    stock: number;
    options: Array<{ option: { value: string } | null }>;
  }>;
};

function productToSearchDoc(p: ProductForSearchDoc): ProductSearchDoc {
  let priceMin = p.price;
  let priceMax = p.price;
  let totalStock = p.stock;

  if (p.hasVariants && p.variants.length > 0) {
    const prices = p.variants.map((v) => v.price);
    priceMin = Math.min(...prices);
    priceMax = Math.max(...prices);
    totalStock = p.variants.reduce((sum, v) => sum + v.stock, 0);
  }

  return {
    id: p.id,
    slug: p.slug,
    name: p.name,
    description: p.description ?? "",
    category_id: p.categoryId,
    category_slug: p.category?.slug ?? null,
    category_name: p.category?.name ?? null,
    brand_id: p.brandId,
    brand_slug: p.brand?.slug ?? null,
    brand_name: p.brand?.name ?? null,
    variant_names: Array.from(
      new Set(
        p.variants
          .flatMap((variant) => variant.options.map((vo) => vo.option?.value))
          .filter((value): value is string => Boolean(value))
      )
    ),
    sku_codes: p.variants.map((variant) => variant.sku).filter((sku): sku is string => Boolean(sku)),
    price_min: priceMin,
    price_max: priceMax,
    discount_price: p.discountPrice,
    stock: p.stock,
    total_stock: totalStock,
    weight_grams: p.weightGram,
    avg_rating: p.avgRating,
    review_count: p.reviewCount,
    created_at: Math.floor(p.createdAt.getTime() / 1000),
    image_url: p.imageUrl,
    is_active: p.isActive,
    has_variants: p.hasVariants,
  };
}

function normalizeSearchText(value: string) {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function tokenizeSearchQuery(query: string) {
  return normalizeSearchText(query)
    .split(/\s+/)
    .map((token) => token.trim())
    .filter((token) => token.length >= 2);
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

  const maxDistance = token.length <= 4 ? 1 : 2;
  return (
    Math.abs(word.length - token.length) <= maxDistance &&
    levenshtein(token, word) <= maxDistance
  );
}

function searchFields(item: ProductSearchDoc) {
  return [
    item.name,
    item.description,
    item.category_name,
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
  const category = normalizeSearchText(item.category_name ?? "");
  const fields = searchFields(item).map(normalizeSearchText).join(" ");

  let score = 0;
  if (name === normalizedQuery) score += 120;
  if (name.startsWith(normalizedQuery)) score += 90;
  if (name.includes(normalizedQuery)) score += 70;
  if (brand === normalizedQuery) score += 80;
  if (brand.includes(normalizedQuery)) score += 55;
  if (category.includes(normalizedQuery)) score += 35;

  for (const token of tokens) {
    if (name.includes(token)) score += 18;
    else if (brand.includes(token)) score += 14;
    else if (category.includes(token)) score += 10;
    else if (fields.includes(token)) score += 4;
  }

  return score;
}

async function searchProductsFromDb(opts: Required<Pick<SearchOptions, "q" | "categorySlug" | "brandSlug" | "sort" | "page" | "perPage">> &
  Pick<SearchOptions, "minPrice" | "maxPrice" | "inStock" | "minRating">) {
  const start = Date.now();
  const q = opts.q.trim();
  const queryTokens = tokenizeSearchQuery(q);
  const searchOr = q
    ? [
        { name: { contains: q, mode: "insensitive" as const } },
        { description: { contains: q, mode: "insensitive" as const } },
        { category: { name: { contains: q, mode: "insensitive" as const } } },
        { brand: { name: { contains: q, mode: "insensitive" as const } } },
        { variants: { some: { sku: { contains: q, mode: "insensitive" as const } } } },
        ...queryTokens.flatMap((token) => [
          { name: { contains: token, mode: "insensitive" as const } },
          { description: { contains: token, mode: "insensitive" as const } },
          { category: { name: { contains: token, mode: "insensitive" as const } } },
          { brand: { name: { contains: token, mode: "insensitive" as const } } },
          { variants: { some: { sku: { contains: token, mode: "insensitive" as const } } } },
        ]),
      ]
    : undefined;

  const products = await prisma.product.findMany({
    where: {
      isActive: true,
      ...(opts.categorySlug.length > 0 ? { category: { slug: { in: opts.categorySlug } } } : {}),
      ...(opts.brandSlug.length > 0 ? { brand: { slug: { in: opts.brandSlug } } } : {}),
      ...(searchOr ? { OR: searchOr } : {}),
    },
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

  let items = products.map((product) => productToSearchDoc(product as ProductForSearchDoc));

  if (q) {
    items = items.filter((item) => matchesSearchQuery(item, q));
  }
  if (opts.minPrice !== undefined && Number.isFinite(opts.minPrice)) {
    items = items.filter((item) => item.price_min >= Math.max(0, opts.minPrice!));
  }
  if (opts.maxPrice !== undefined && Number.isFinite(opts.maxPrice)) {
    items = items.filter((item) => item.price_min <= Math.max(0, opts.maxPrice!));
  }
  if (opts.inStock) {
    items = items.filter((item) => item.total_stock > 0);
  }
  if (opts.minRating !== undefined && Number.isFinite(opts.minRating)) {
    items = items.filter((item) => item.avg_rating >= opts.minRating!);
  }

  items.sort((a, b) => {
    if (opts.sort === "price_asc") return a.price_min - b.price_min;
    if (opts.sort === "price_desc") return b.price_min - a.price_min;
    if (opts.sort === "newest") return b.created_at - a.created_at;
    if (opts.sort === "rating_desc") return b.avg_rating - a.avg_rating || b.review_count - a.review_count;
    if (opts.sort === "best_seller") return b.review_count - a.review_count;
    return relevanceScore(b, q) - relevanceScore(a, q);
  });

  const limit = Math.max(1, Math.min(60, opts.perPage));
  const offset = Math.max(0, (opts.page - 1) * limit);
  const paged = items.slice(offset, offset + limit);

  return {
    items: paged,
    total: items.length,
    page: opts.page,
    per_page: limit,
    took_ms: Date.now() - start,
    degraded: true,
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
    sort = "relevance",
    page = 1,
    perPage = 24,
  } = opts;

  const filters: string[] = ["is_active = true"];

  if (categorySlug.length > 0) {
    const escaped = categorySlug.map((c) => `category_slug = "${c.replace(/"/g, '\\"')}"`);
    filters.push(`(${escaped.join(" OR ")})`);
  }
  if (brandSlug.length > 0) {
    const escaped = brandSlug.map((b) => `brand_slug = "${b.replace(/"/g, '\\"')}"`);
    filters.push(`(${escaped.join(" OR ")})`);
  }
  if (minPrice !== undefined && Number.isFinite(minPrice)) {
    filters.push(`price_min >= ${Math.max(0, minPrice)}`);
  }
  if (maxPrice !== undefined && Number.isFinite(maxPrice)) {
    filters.push(`price_min <= ${Math.max(0, maxPrice)}`);
  }
  if (inStock) {
    filters.push("total_stock > 0");
  }
  if (minRating !== undefined && Number.isFinite(minRating)) {
    filters.push(`avg_rating >= ${minRating}`);
  }

  const limit = Math.max(1, Math.min(60, perPage));
  const offset = Math.max(0, (page - 1) * limit);

  const start = Date.now();
  try {
    const result = await productIndex.search<ProductSearchDoc>(q, {
      filter: filters.join(" AND "),
      sort: SORT_MAP[sort],
      limit,
      offset,
    });

    return {
      items: result.hits,
      total: result.estimatedTotalHits ?? result.hits.length,
      page,
      per_page: limit,
      took_ms: Date.now() - start,
    };
  } catch (error) {
    console.warn("[searchProducts] Meilisearch unavailable, falling back to database:", error);
    return searchProductsFromDb({
      q,
      categorySlug,
      brandSlug,
      minPrice,
      maxPrice,
      inStock,
      minRating,
      sort,
      page,
      perPage: limit,
    });
  }
}
