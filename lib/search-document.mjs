export const SEARCHABLE_ATTRIBUTES = [
  "name",
  "brand_name",
  "variant_names",
  "sku_codes",
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

/**
 * Build denormalized search text untuk kolom Product.searchText.
 * Digabung dari: name + brand_name + category_name + variant_names + sku_codes.
 *
 * Hasil lowercase, deduped, single space — siap untuk ILIKE / trigram similarity.
 * Dipakai oleh DB-fallback search (pg_trgm GIN index) supaya tetap fast +
 * typo-tolerant tanpa Meilisearch.
 */
export function buildProductSearchText(product) {
  const activeVariants = (product.variants ?? []).filter(
    (variant) => !variant.deletedAt && variant.isActive,
  );

  const variantNames = activeVariants
    .flatMap((variant) => (variant.options ?? []).map((vo) => vo.option?.value))
    .filter(Boolean);

  const skuCodes = activeVariants.map((variant) => variant.sku).filter(Boolean);

  const parts = [
    product.name,
    product.brand?.name,
    product.category?.name,
    ...variantNames,
    ...skuCodes,
  ].filter(Boolean);

  return Array.from(new Set(parts.map((part) => String(part).toLowerCase())))
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Apply Flash Sale + Promo Toko priority chain (lowest wins). Inline
 * version dari lib/product-pricing.ts:resolveActiveDiscount() — .mjs
 * tidak bisa import .ts langsung.
 *
 * @param basePrice harga base produk
 * @param flashSale { discountPrice, endsAt } Flash Sale data
 * @param promoItems ProductDiscountItem aktif (filtered di query)
 * @returns effective price atau null kalau tidak ada discount
 */
function resolveEffectivePrice(basePrice, flashSale, promoItems, now) {
  const t = now ?? new Date();
  let best = null;

  if (
    flashSale &&
    flashSale.endsAt &&
    flashSale.endsAt > t &&
    flashSale.discountPrice &&
    flashSale.discountPrice > 0 &&
    flashSale.discountPrice < basePrice
  ) {
    best = flashSale.discountPrice;
  }

  for (const item of promoItems ?? []) {
    if (!item.endsAt || item.endsAt <= t) continue;
    if (!item.discountedPrice || item.discountedPrice <= 0) continue;
    if (item.discountedPrice >= basePrice) continue;
    if (best === null || item.discountedPrice < best) {
      best = item.discountedPrice;
    }
  }

  return best;
}

export function productToSearchDoc(product) {
  const activeVariants = (product.variants ?? []).filter(
    (variant) => !variant.deletedAt && variant.isActive,
  );
  const now = new Date();

  let priceMin = product.price;
  let priceMax = product.price;
  let totalStock = product.stock;

  if (product.hasVariants && activeVariants.length > 0) {
    const prices = activeVariants.map((variant) => variant.price);
    priceMin = Math.min(...prices);
    priceMax = Math.max(...prices);
    totalStock = activeVariants.reduce((sum, variant) => sum + variant.stock, 0);
  }

  // Apply Flash Sale + Promo Toko priority. Untuk variant products,
  // hitung MIN effective price across variants. Untuk single product,
  // langsung apply ke product.price.
  const discountItems = product.discountItems ?? [];
  let discountPrice = null;

  if (product.hasVariants && activeVariants.length > 0) {
    const effectivePrices = activeVariants.map((v) => {
      const variantPromoItems = discountItems
        .filter((it) => it.variantId === v.id)
        .map((it) => ({
          discountedPrice: it.discountedPrice,
          endsAt: it.discount?.endsAt,
        }));
      // Flash Sale ratio dari product → variant
      const flashSale =
        product.flashSaleEndsAt && product.discountPrice && product.price > 0
          ? {
              discountPrice: Math.round(
                v.price * (product.discountPrice / product.price),
              ),
              endsAt: product.flashSaleEndsAt,
            }
          : null;
      const effective = resolveEffectivePrice(
        v.price,
        flashSale,
        variantPromoItems,
        now,
      );
      return effective ?? v.price;
    });
    const minEffective = Math.min(...effectivePrices);
    if (minEffective < priceMin) {
      discountPrice = minEffective;
    }
  } else {
    // Single product
    const promoItems = discountItems
      .filter((it) => it.variantId === null)
      .map((it) => ({
        discountedPrice: it.discountedPrice,
        endsAt: it.discount?.endsAt,
      }));
    discountPrice = resolveEffectivePrice(
      product.price,
      {
        discountPrice: product.discountPrice,
        endsAt: product.flashSaleEndsAt,
      },
      promoItems,
      now,
    );
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
    discount_price: discountPrice,
    member_price:
      typeof product.memberPrice === "number" && product.memberPrice > 0
        ? product.memberPrice
        : null,
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
