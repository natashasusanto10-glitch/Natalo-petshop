import type { SearchSort } from "@/lib/search";

/**
 * Penerjemah URL halaman /products.
 *
 * `/products` memakai `kategori` (bahasa Indonesia) sebagai param resmi karena
 * banner DB, hero, nav kategori, dan beranda semua menautkannya. `/api/search`
 * memakai `category`. Semua penerjemahan — termasuk param lama yang sudah tidak
 * punya padanan — dikurung di file ini supaya tidak tersebar.
 */

export const PRODUCTS_DEFAULT_SORT: SearchSort = "best_seller";
export const PRODUCTS_PER_PAGE = 24;

export type ProductsCatalogParams = {
  q: string;
  categorySlugs: string[];
  brandSlugs: string[];
  minPrice?: number;
  maxPrice?: number;
  inStock: boolean;
  minRating?: number;
  discountOnly: boolean;
  sort: SearchSort;
  page: number;
};

const MODERN_SORTS: SearchSort[] = [
  "relevance",
  "price_asc",
  "price_desc",
  "newest",
  "rating_desc",
  "best_seller",
  "trending",
];

/** Alias yang dipakai nav desktop. Sebelum PR4 ketiganya TIDAK menyaring apa pun. */
const SORT_ALIASES: Record<string, SearchSort> = {
  terlaris: "best_seller",
  baru: "newest",
  promo: PRODUCTS_DEFAULT_SORT,
};

/** Param `popular` lama. `most-searched`/`most-bought` tidak punya padanan — terlaris paling dekat. */
const POPULAR_SORTS: Record<string, SearchSort> = {
  "best-seller": "best_seller",
  trending: "trending",
  "highest-rating": "rating_desc",
  "most-searched": "best_seller",
  "most-bought": "best_seller",
};

function nonNegativeNumber(raw: string | null): number | undefined {
  if (!raw) return undefined;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 ? value : undefined;
}

function positiveNumber(raw: string | null): number | undefined {
  const value = nonNegativeNumber(raw);
  return value !== undefined && value > 0 ? value : undefined;
}

export function parseProductsParams(sp: URLSearchParams): ProductsCatalogParams {
  const rawSort = sp.get("sort");

  // `sort=promo` hanya menyaring diskon; urutannya tetap default.
  const discountOnly =
    sp.get("discount_only") === "true" ||
    sp.get("promo") === "1" ||
    sp.get("diskon") === "1" ||
    rawSort === "promo";

  // `Object.hasOwn` mencegah kunci prototype bawaan (mis. "constructor",
  // "toString") ikut terbaca sebagai entri tabel yang valid — tanpa guard ini
  // `?sort=constructor` atau `?popular=toString` bisa meloloskan nilai fungsi
  // bawaan JS ke `sort`. Hasil akhirnya tetap divalidasi ulang ke MODERN_SORTS
  // supaya `sort` yang dikembalikan selalu salah satu dari 7 SearchSort.
  let sort: SearchSort | undefined;
  if (rawSort && (MODERN_SORTS as string[]).includes(rawSort)) {
    sort = rawSort as SearchSort;
  } else if (rawSort && Object.hasOwn(SORT_ALIASES, rawSort)) {
    sort = SORT_ALIASES[rawSort];
  } else {
    const popular = sp.get("popular");
    if (popular && Object.hasOwn(POPULAR_SORTS, popular)) sort = POPULAR_SORTS[popular];
    // Batas 30-hari dibuang (owner §4.8); "terbaru dulu" tak pernah kosong.
    else if (sp.get("new")) sort = "newest";
  }
  if (sort && !(MODERN_SORTS as string[]).includes(sort)) sort = undefined;

  // Simetris dengan buildApiSearchParams/buildProductsHref yang menulis
  // banyak nilai kategori (forEach/append) — getAll() supaya round-trip setia.
  const rawKategori = sp.getAll("kategori");
  const categoryValues = rawKategori.length > 0 ? rawKategori : sp.getAll("category");
  const categorySlugs = categoryValues.filter((slug) => slug && slug !== "all");

  const page = Number(sp.get("page"));

  return {
    q: (sp.get("q") ?? "").trim(),
    categorySlugs,
    brandSlugs: [...new Set(sp.getAll("brand").filter(Boolean))],
    minPrice: nonNegativeNumber(sp.get("min_price")),
    maxPrice: nonNegativeNumber(sp.get("max_price")),
    inStock: sp.get("in_stock") === "true",
    minRating: positiveNumber(sp.get("min_rating")),
    discountOnly,
    sort: sort ?? PRODUCTS_DEFAULT_SORT,
    page: Number.isFinite(page) && page >= 1 ? Math.floor(page) : 1,
  };
}

export function buildApiSearchParams(p: ProductsCatalogParams): URLSearchParams {
  const params = new URLSearchParams();
  if (p.q) params.set("q", p.q);
  p.categorySlugs.forEach((slug) => params.append("category", slug));
  p.brandSlugs.forEach((slug) => params.append("brand", slug));
  if (p.minPrice !== undefined) params.set("min_price", String(p.minPrice));
  if (p.maxPrice !== undefined) params.set("max_price", String(p.maxPrice));
  if (p.inStock) params.set("in_stock", "true");
  if (p.minRating !== undefined) params.set("min_rating", String(p.minRating));
  if (p.discountOnly) params.set("discount_only", "true");
  params.set("sort", p.sort);
  params.set("page", String(p.page));
  params.set("per_page", String(PRODUCTS_PER_PAGE));
  return params;
}

/** URL kanonis `/products` — selalu menulis `kategori`, tidak pernah param lama. */
export function buildProductsHref(p: ProductsCatalogParams): string {
  const params = new URLSearchParams();
  if (p.q) params.set("q", p.q);
  p.categorySlugs.forEach((slug) => params.append("kategori", slug));
  p.brandSlugs.forEach((slug) => params.append("brand", slug));
  if (p.minPrice !== undefined) params.set("min_price", String(p.minPrice));
  if (p.maxPrice !== undefined) params.set("max_price", String(p.maxPrice));
  if (p.inStock) params.set("in_stock", "true");
  if (p.minRating !== undefined) params.set("min_rating", String(p.minRating));
  if (p.discountOnly) params.set("discount_only", "true");
  if (p.sort !== PRODUCTS_DEFAULT_SORT) params.set("sort", p.sort);
  if (p.page > 1) params.set("page", String(p.page));
  const query = params.toString();
  return query ? `/products?${query}` : "/products";
}
