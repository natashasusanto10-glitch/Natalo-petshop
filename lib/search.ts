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
  total_stock: number;
  weight_grams: number;
  avg_rating: number;
  review_count: number;
  created_at: number; // unix seconds
  image_url: string | null;
  is_active: boolean;
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
    total_stock: totalStock,
    weight_grams: p.weightGram,
    avg_rating: p.avgRating,
    review_count: p.reviewCount,
    created_at: Math.floor(p.createdAt.getTime() / 1000),
    image_url: p.imageUrl,
    is_active: p.isActive,
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
  | "rating_desc";

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
};

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
}
