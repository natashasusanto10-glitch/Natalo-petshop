"use client";

export type CachedCategorySummary = {
  id: string;
  name: string;
  slug: string;
  productCount: number;
  imageUrl: string | null;
};

const CATEGORY_CACHE_KEY = "natalo:categories:v1";
const CATEGORY_CACHE_TTL_MS = 5 * 60 * 1000;

type CategoryCache = {
  savedAt: number;
  categories: CachedCategorySummary[];
};

export function readCategoryCache(): CategoryCache | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(CATEGORY_CACHE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as CategoryCache;
    if (!Array.isArray(parsed.categories)) return null;
    return parsed;
  } catch {
    window.localStorage.removeItem(CATEGORY_CACHE_KEY);
    return null;
  }
}

export function writeCategoryCache(categories: CachedCategorySummary[]) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(
    CATEGORY_CACHE_KEY,
    JSON.stringify({ savedAt: Date.now(), categories })
  );
}

export function isCategoryCacheFresh(cache: CategoryCache | null) {
  return Boolean(cache && Date.now() - cache.savedAt < CATEGORY_CACHE_TTL_MS);
}

export function prefetchCategories() {
  if (typeof window === "undefined") return;
  if (isCategoryCacheFresh(readCategoryCache())) return;

  void fetch("/api/categories", { cache: "force-cache" })
    .then((response) => (response.ok ? response.json() : null))
    .then((payload) => {
      if (Array.isArray(payload?.categories)) writeCategoryCache(payload.categories);
    })
    .catch(() => {});
}
