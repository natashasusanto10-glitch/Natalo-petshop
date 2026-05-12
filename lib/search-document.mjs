export const SEARCHABLE_ATTRIBUTES = [
  "name",
  "brand_name",
  "category_name",
  "variant_names",
  "sku_codes",
  "description",
];

export const FILTERABLE_ATTRIBUTES = [
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
];

export const SORTABLE_ATTRIBUTES = [
  "price_min",
  "created_at",
  "avg_rating",
  "review_count",
];

export const SYNONYMS = {
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

export const TYPO_TOLERANCE = {
  enabled: true,
  minWordSizeForTypos: { oneTypo: 4, twoTypos: 8 },
};

export function productToSearchDoc(product) {
  const activeVariants = (product.variants ?? []).filter(
    (variant) => !variant.deletedAt && variant.isActive,
  );

  let priceMin = product.price;
  let priceMax = product.price;
  let totalStock = product.stock;

  if (product.hasVariants && activeVariants.length > 0) {
    const prices = activeVariants.map((variant) => variant.price);
    priceMin = Math.min(...prices);
    priceMax = Math.max(...prices);
    totalStock = activeVariants.reduce((sum, variant) => sum + variant.stock, 0);
  }

  const variantNames = Array.from(
    new Set(
      activeVariants
        .flatMap((variant) => (variant.options ?? []).map((vo) => vo.option?.value))
        .filter(Boolean),
    ),
  );

  const skuCodes = activeVariants.map((variant) => variant.sku).filter(Boolean);

  return {
    id: product.id,
    slug: product.slug,
    name: product.name,
    description: product.description ?? "",
    category_id: product.categoryId,
    category_slug: product.category?.slug ?? null,
    category_name: product.category?.name ?? null,
    brand_id: product.brandId,
    brand_slug: product.brand?.slug ?? null,
    brand_name: product.brand?.name ?? null,
    variant_names: variantNames,
    sku_codes: skuCodes,
    price_min: priceMin,
    price_max: priceMax,
    discount_price: product.discountPrice ?? null,
    stock: totalStock,
    total_stock: totalStock,
    weight_grams: product.weightGram,
    avg_rating: product.avgRating,
    review_count: product.reviewCount,
    created_at: Math.floor(product.createdAt.getTime() / 1000),
    image_url: product.imageUrl,
    is_active: product.isActive,
    has_variants: product.hasVariants,
  };
}

function ensureTaskSucceeded(task) {
  if (task && "status" in task && task.status !== "succeeded") {
    throw new Error(`Meilisearch task ${task.uid ?? task.taskUid ?? "unknown"} failed: ${JSON.stringify(task.error ?? task)}`);
  }
  return task;
}

export async function applyProductIndexSettings(index, options = {}) {
  const wait = Boolean(options.wait);
  const waitOptions = options.waitOptions;
  const tasks = [
    index.updateSearchableAttributes(SEARCHABLE_ATTRIBUTES),
    index.updateFilterableAttributes(FILTERABLE_ATTRIBUTES),
    index.updateSortableAttributes(SORTABLE_ATTRIBUTES),
    index.updateSynonyms(SYNONYMS),
    index.updateTypoTolerance(TYPO_TOLERANCE),
  ];

  if (!wait) return Promise.all(tasks);

  const completed = [];
  for (const taskPromise of tasks) {
    if (typeof taskPromise.waitTask === "function") {
      completed.push(ensureTaskSucceeded(await taskPromise.waitTask(waitOptions)));
    } else {
      completed.push(await taskPromise);
    }
  }
  return completed;
}
