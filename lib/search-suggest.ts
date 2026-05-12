export type SuggestProduct = {
  id: string;
  slug: string;
  name: string;
  image_url: string | null;
  price_min: number;
  price_max: number;
  brand_name: string | null;
};

export type SuggestLabel = {
  slug: string;
  name: string;
  count: number;
};

export type SuggestResponse = {
  products: SuggestProduct[];
  categories: SuggestLabel[];
  brands: SuggestLabel[];
  total: number;
};

export const EMPTY_SUGGEST_RESPONSE: SuggestResponse = {
  products: [],
  categories: [],
  brands: [],
  total: 0,
};

export function mergeUnique<T extends { slug?: string; id?: string }>(
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

export function mergeSuggestionProducts({
  dbProducts,
  meiliProducts,
  limit,
}: {
  dbProducts: SuggestProduct[];
  meiliProducts: SuggestProduct[];
  limit: number;
}) {
  return mergeUnique(dbProducts, meiliProducts, limit);
}
