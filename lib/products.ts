import { prisma } from "@/lib/prisma";
import {
  attachPublicProductVoucherPreviews,
  type ProductVoucherPreview,
} from "@/lib/product-vouchers";
import { resolveActiveDiscount } from "@/lib/product-pricing";
import { sampleProducts } from "@/lib/sample-data";
import type { OrderStatus, Prisma } from "@prisma/client";

export type StoreVariantOption = {
  id: string;
  value: string;
  position: number;
};

export type StoreVariantAttribute = {
  id: string;
  name: string;
  position: number;
  options: StoreVariantOption[];
};

export type StoreProductVariant = {
  id: string;
  sku: string | null;
  price: number;
  stock: number;
  weightGram: number;
  imageUrl: string | null;
  isActive: boolean;
  deletedAt: Date | null;
  options: { optionId: string }[];
};

export type StoreProduct = {
  id: string;
  name: string;
  slug: string;
  description: string;
  price: number;
  discountPrice: number | null;
  memberPrice?: number | null;
  stock: number;
  weightGram: number;
  imageUrl: string | null;
  gallery: string[];
  hasVariants: boolean;
  avgRating: number;
  reviewCount: number;
  soldCount?: number;
  categoryId?: string | null;
  categorySlug?: string | null;
  voucherPreview?: ProductVoucherPreview | null;
  shippingVoucherPreview?: ProductVoucherPreview | null;
  /** ISO timestamp — kalau di-set, admin explicit tag produk ini Flash
   *  Sale sampai waktu ini. SELALU masuk Flash Sale section apapun
   *  discount %-nya, dengan countdown. Kalau null, masuk Flash Sale
   *  hanya kalau discount >= FLASH_SALE_MIN_DISCOUNT_PERCENT (auto). */
  flashSaleEndsAt?: string | null;
  // hanya diisi oleh getProductBySlug
  variantAttrs?: StoreVariantAttribute[];
  variants?: StoreProductVariant[];
};

/**
 * Threshold minimum discount % untuk auto-include produk ke Flash Sale
 * section di home (tanpa admin explicit tag). Default 20% — match
 * konvensi Tokopedia/Shopee Flash Sale. Override via env atau bump
 * constant kalau perlu.
 *
 * Logic 3-tier:
 *   1. flashSaleEndsAt IS NOT NULL AND > now() → SELALU masuk (countdown)
 *   2. flashSaleEndsAt IS NULL AND discount >= threshold → masuk (no countdown)
 *   3. flashSaleEndsAt expired (< now) → auto-exclude
 */
export const FLASH_SALE_MIN_DISCOUNT_PERCENT = 20;

function normalizeProductWeight(
  name: string,
  slug: string,
  weightGram: number
) {
  const text = `${name} ${slug}`.toLowerCase();
  if (text.includes("maxi-cat") && text.includes("20kg")) return 20000;
  return weightGram;
}

const variantInclude = {
  variantAttrs: {
    orderBy: { position: "asc" as const },
    include: { options: { orderBy: { position: "asc" as const } } },
  },
  variants: {
    where: { deletedAt: null },
    include: { options: { select: { optionId: true } } },
    orderBy: { createdAt: "asc" as const },
  },
};

// BUG FIX: sebelumnya productListInclude adalah const dengan
// `new Date()` di dalamnya — dievaluasi SEKALI saat module load,
// jadi promo yang dibuat setelah deploy tidak match. Sekarang wrap
// di function supaya `new Date()` fresh per call.
function getProductListInclude() {
  const now = new Date();
  return {
    category: { select: { id: true, slug: true } },
    variants: {
      where: { deletedAt: null, isActive: true },
      select: { id: true, price: true, stock: true },
    },
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
  } satisfies Prisma.ProductInclude;
}

type ProductListRecord = Prisma.ProductGetPayload<{
  include: ReturnType<typeof getProductListInclude>;
}>;

function mapProductListRecord(p: ProductListRecord): StoreProduct {
  if (p.hasVariants && p.variants.length > 0) {
    // Untuk produk berVarian, pricing per-variant. Hitung MIN effective
    // price dari semua varian aktif setelah apply discount item match.
    const variantPrices = p.variants.map((v) => {
      const variantPromoItems = p.discountItems
        .filter((it) => it.variantId === v.id)
        .map((it) => ({
          discountedPrice: it.discountedPrice,
          endsAt: it.discount.endsAt,
        }));
      const discount = resolveActiveDiscount(
        v.price,
        // Flash Sale ratio applied (untuk variant, kalau Flash Sale ada
        // di parent, pakai ratio dari product.price ke product.discountPrice
        // dan apply ke variant.price)
        flashSaleForVariant(p.price, p.discountPrice, p.flashSaleEndsAt, v.price),
        variantPromoItems,
      );
      return discount ? discount.effectivePrice : v.price;
    });
    const minPrice = Math.min(...variantPrices);
    const totalStock = p.variants.reduce((s, v) => s + v.stock, 0);
    // discountPrice di-set ke minPrice kalau lebih rendah dari product.price
    // (artinya ada diskon aktif di variant terendah).
    const showDiscount = minPrice < Math.min(...p.variants.map((v) => v.price));

    return {
      id: p.id,
      name: p.name,
      slug: p.slug,
      description: p.description,
      price: Math.min(...p.variants.map((v) => v.price)),
      discountPrice: showDiscount ? minPrice : null,
      memberPrice: p.memberPrice,
      stock: totalStock,
      weightGram: normalizeProductWeight(p.name, p.slug, p.weightGram),
      imageUrl: p.imageUrl,
      gallery: p.gallery ?? [],
      hasVariants: true,
      avgRating: p.avgRating,
      reviewCount: p.reviewCount,
      categoryId: p.category?.id ?? null,
      categorySlug: p.category?.slug ?? null,
      voucherPreview: null,
      shippingVoucherPreview: null,
      flashSaleEndsAt: p.flashSaleEndsAt?.toISOString() ?? null,
    };
  }

  // Produk single (no variants) — apply discount langsung.
  const promoItems = p.discountItems
    .filter((it) => it.variantId === null)
    .map((it) => ({
      discountedPrice: it.discountedPrice,
      endsAt: it.discount.endsAt,
    }));
  const discount = resolveActiveDiscount(
    p.price,
    { discountPrice: p.discountPrice, endsAt: p.flashSaleEndsAt },
    promoItems,
  );

  // Override discountPrice dengan effective dari resolver. Source:
  //  - FLASH_SALE: keep flashSaleEndsAt (countdown timer di customer side)
  //  - PROMO_TOKO: clear flashSaleEndsAt supaya tidak salah tampil
  //    countdown (Promo Toko bukan urgency-driven).
  const effectiveDiscountPrice = discount ? discount.effectivePrice : null;
  const effectiveFlashSaleEndsAt =
    discount?.source === "FLASH_SALE"
      ? p.flashSaleEndsAt?.toISOString() ?? null
      : null;

  return {
    id: p.id,
    name: p.name,
    slug: p.slug,
    description: p.description,
    price: p.price,
    discountPrice: effectiveDiscountPrice,
    memberPrice: p.memberPrice,
    stock: p.stock,
    weightGram: normalizeProductWeight(p.name, p.slug, p.weightGram),
    imageUrl: p.imageUrl,
    gallery: p.gallery ?? [],
    hasVariants: false,
    avgRating: p.avgRating,
    reviewCount: p.reviewCount,
    categoryId: p.category?.id ?? null,
    categorySlug: p.category?.slug ?? null,
    voucherPreview: null,
    shippingVoucherPreview: null,
    flashSaleEndsAt: effectiveFlashSaleEndsAt,
  };
}

/**
 * Hitung Flash Sale price untuk variant tertentu — pakai ratio
 * dari (product.discountPrice / product.price) × variant.price.
 * Karena Flash Sale di-set di product level (single discountPrice),
 * tapi setiap variant punya base price sendiri.
 */
function flashSaleForVariant(
  productPrice: number,
  productDiscountPrice: number | null,
  flashEnd: Date | null,
  variantPrice: number,
): { discountPrice: number | null; endsAt: Date | null } {
  if (!flashEnd || !productDiscountPrice || productPrice <= 0) {
    return { discountPrice: null, endsAt: null };
  }
  const ratio = productDiscountPrice / productPrice;
  return {
    discountPrice: Math.round(variantPrice * ratio),
    endsAt: flashEnd,
  };
}

async function withVoucherPreviews(
  products: StoreProduct[],
  viewerId?: string | null
) {
  return attachPublicProductVoucherPreviews(products, { userId: viewerId });
}

async function withSoldCounts(
  products: StoreProduct[]
): Promise<StoreProduct[]> {
  if (products.length === 0) return products;

  const productIds = products.map((product) => product.id);
  const rows = await prisma.orderItem.groupBy({
    by: ["productId"],
    where: {
      productId: { in: productIds },
      order: {
        paymentStatus: "PAID",
        status: { in: VALID_SALES_ORDER_STATUSES },
      },
    },
    _sum: { quantity: true },
  });

  const soldByProductId = new Map(
    rows.map((row) => [row.productId, row._sum.quantity ?? 0])
  );

  return products.map((product) => ({
    ...product,
    soldCount: soldByProductId.get(product.id) ?? 0,
  }));
}

async function withProductListMeta(
  products: StoreProduct[],
  viewerId?: string | null
) {
  return withVoucherPreviews(await withSoldCounts(products), viewerId);
}

export type NewProductFilter =
  | "today"
  | "this-week"
  | "this-month"
  | "last-30-days"
  | "newest";
export type PopularFilter =
  | "best-seller"
  | "trending"
  | "most-searched"
  | "highest-rating"
  | "most-bought";

const VALID_SALES_ORDER_STATUSES: OrderStatus[] = [
  "PAID",
  "PROCESSING",
  "READY_FOR_PICKUP",
  "SHIPPED",
  "DELIVERED",
];

const TRENDING_WINDOW_DAYS = 14;
const NEW_PRODUCT_WINDOW_DAYS = 30;
const SEARCH_POPULAR_WINDOW_DAYS = 30;
const WIB_OFFSET_MS = 7 * 60 * 60 * 1000;

function isOrderDrivenPopularFilter(filter?: PopularFilter) {
  return (
    filter === "best-seller" ||
    filter === "most-bought" ||
    filter === "trending"
  );
}

function toAndArray(and: Prisma.ProductWhereInput["AND"]) {
  if (!and) return [];
  return Array.isArray(and) ? and : [and];
}

function withAnd(
  where: Prisma.ProductWhereInput,
  condition: Prisma.ProductWhereInput
): Prisma.ProductWhereInput {
  return {
    ...where,
    AND: [...toAndArray(where.AND), condition],
  };
}

function startOfWibDay(date = new Date()) {
  const wibDate = new Date(date.getTime() + WIB_OFFSET_MS);
  return new Date(
    Date.UTC(
      wibDate.getUTCFullYear(),
      wibDate.getUTCMonth(),
      wibDate.getUTCDate()
    ) - WIB_OFFSET_MS
  );
}

function startOfWibWeek(date = new Date()) {
  const wibDate = new Date(date.getTime() + WIB_OFFSET_MS);
  const dayOfWeek = wibDate.getUTCDay();
  const daysSinceMonday = (dayOfWeek + 6) % 7;
  const weekStart = new Date(
    Date.UTC(
      wibDate.getUTCFullYear(),
      wibDate.getUTCMonth(),
      wibDate.getUTCDate()
    ) - WIB_OFFSET_MS
  );
  weekStart.setUTCDate(weekStart.getUTCDate() - daysSinceMonday);
  return weekStart;
}

function daysAgo(date: Date, days: number) {
  return new Date(date.getTime() - days * 24 * 60 * 60 * 1000);
}

/**
 * Filter "Produk Baru" memakai `createdAt` produk admin/dashboard.
 * Boundary hari dan minggu dihitung dengan timezone WIB agar hasil mobile user
 * Indonesia tidak bergeser karena UTC/server timezone.
 */
function newProductCutoff(filter: NewProductFilter | undefined): Date | null {
  if (!filter) return null;
  const now = new Date();
  if (filter === "today") return startOfWibDay(now);
  if (filter === "this-week") return startOfWibWeek(now);
  if (
    filter === "this-month" ||
    filter === "last-30-days" ||
    filter === "newest"
  ) {
    return daysAgo(now, NEW_PRODUCT_WINDOW_DAYS);
  }
  return null;
}

function wibDateKey(date: Date) {
  return new Date(date.getTime() + WIB_OFFSET_MS).toISOString().slice(0, 10);
}

function productRankWhere(
  where: Prisma.ProductWhereInput
): Prisma.ProductWhereInput {
  return withAnd(where, {
    OR: [
      { hasVariants: false, price: { gt: 0 }, stock: { gt: 0 } },
      {
        hasVariants: true,
        variants: {
          some: {
            deletedAt: null,
            isActive: true,
            price: { gt: 0 },
            stock: { gt: 0 },
          },
        },
      },
    ],
  });
}

async function getBestSellerProductIds({
  productWhere,
  take,
  skip,
}: {
  productWhere: Prisma.ProductWhereInput;
  take?: number;
  skip?: number;
}) {
  const rows = await prisma.orderItem.groupBy({
    by: ["productId"],
    where: {
      order: {
        paymentStatus: "PAID",
        status: { in: VALID_SALES_ORDER_STATUSES },
      },
      product: productRankWhere(productWhere),
    },
    _sum: { quantity: true },
    orderBy: { _sum: { quantity: "desc" } },
    ...(typeof take === "number" ? { take } : {}),
    ...(typeof skip === "number" && skip > 0 ? { skip } : {}),
  });

  return rows.map((row) => row.productId);
}

async function getTrendingProductIds({
  productWhere,
  take,
  skip,
}: {
  productWhere: Prisma.ProductWhereInput;
  take?: number;
  skip?: number;
}) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - TRENDING_WINDOW_DAYS);

  const rows = await prisma.orderItem.findMany({
    where: {
      order: {
        createdAt: { gte: cutoff },
        paymentStatus: "PAID",
        status: { in: VALID_SALES_ORDER_STATUSES },
      },
      product: productRankWhere(productWhere),
    },
    select: {
      productId: true,
      quantity: true,
      order: {
        select: {
          id: true,
          userId: true,
          customerEmail: true,
          customerPhone: true,
          createdAt: true,
        },
      },
    },
  });

  const stats = new Map<
    string,
    { totalSold: number; buyerIds: Set<string>; purchaseDays: Set<string> }
  >();

  for (const row of rows) {
    const productStats = stats.get(row.productId) ?? {
      totalSold: 0,
      buyerIds: new Set<string>(),
      purchaseDays: new Set<string>(),
    };
    productStats.totalSold += row.quantity;
    productStats.buyerIds.add(
      row.order.userId ??
        row.order.customerEmail ??
        row.order.customerPhone ??
        `order:${row.order.id}`
    );
    productStats.purchaseDays.add(wibDateKey(row.order.createdAt));
    stats.set(row.productId, productStats);
  }

  return Array.from(stats.entries())
    .map(([productId, productStats]) => {
      const purchaseFrequencyDays = productStats.purchaseDays.size;
      const trendingScore =
        productStats.totalSold * 0.5 +
        productStats.buyerIds.size * 0.3 +
        purchaseFrequencyDays * 0.2;
      return {
        productId,
        totalSold: productStats.totalSold,
        purchaseFrequencyDays,
        trendingScore,
      };
    })
    .filter((item) => item.totalSold > 0 && item.purchaseFrequencyDays >= 2)
    .sort((a, b) => {
      if (b.trendingScore !== a.trendingScore)
        return b.trendingScore - a.trendingScore;
      if (b.totalSold !== a.totalSold) return b.totalSold - a.totalSold;
      return b.purchaseFrequencyDays - a.purchaseFrequencyDays;
    })
    .slice(skip ?? 0, typeof take === "number" ? (skip ?? 0) + take : undefined)
    .map((item) => item.productId);
}

async function getMostViewedProductIds({
  productWhere,
  take,
  skip,
}: {
  productWhere: Prisma.ProductWhereInput;
  take?: number;
  skip?: number;
}) {
  const cutoff = daysAgo(new Date(), SEARCH_POPULAR_WINDOW_DAYS);
  const rows = await prisma.userProductView.groupBy({
    by: ["productId"],
    where: {
      viewedAt: { gte: cutoff },
      product: productRankWhere(productWhere),
    },
    _count: { productId: true },
    orderBy: { _count: { productId: "desc" } },
    ...(typeof take === "number" ? { take } : {}),
    ...(typeof skip === "number" && skip > 0 ? { skip } : {}),
  });

  return rows.map((row) => row.productId);
}

async function getMostSearchedProductIds({
  productWhere,
  take,
  skip,
}: {
  productWhere: Prisma.ProductWhereInput;
  take?: number;
  skip?: number;
}) {
  const cutoff = daysAgo(new Date(), SEARCH_POPULAR_WINDOW_DAYS);
  const keywordRows = await prisma.searchLog.groupBy({
    by: ["keyword"],
    where: {
      createdAt: { gte: cutoff },
      keyword: { not: "" },
    },
    _count: { keyword: true },
    orderBy: { _count: { keyword: "desc" } },
    take: 60,
  });

  const scores = new Map<string, number>();
  for (const row of keywordRows) {
    const keyword = row.keyword.trim();
    if (!keyword) continue;

    const matches = await prisma.product.findMany({
      where: productRankWhere(
        withAnd(productWhere, {
          OR: [
            { name: { contains: keyword, mode: "insensitive" } },
            { searchText: { contains: keyword, mode: "insensitive" } },
            { brand: { name: { contains: keyword, mode: "insensitive" } } },
            { category: { name: { contains: keyword, mode: "insensitive" } } },
          ],
        })
      ),
      select: { id: true },
      take: 24,
    });

    for (const product of matches) {
      scores.set(
        product.id,
        (scores.get(product.id) ?? 0) + row._count.keyword
      );
    }
  }

  const rankedIds = Array.from(scores.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(skip ?? 0, typeof take === "number" ? (skip ?? 0) + take : undefined)
    .map(([productId]) => productId);

  if (rankedIds.length) return rankedIds;

  return getMostViewedProductIds({ productWhere, take, skip });
}

function buildOrderBy(
  newFilter?: NewProductFilter,
  popularFilter?: PopularFilter
):
  | Prisma.ProductOrderByWithRelationInput
  | Prisma.ProductOrderByWithRelationInput[] {
  // Popular filter has priority over new filter for ordering
  if (popularFilter === "highest-rating") {
    return [{ avgRating: "desc" }, { reviewCount: "desc" }];
  }
  // "New" filter — admin-friendly strict createdAt sort, jangan
  // di-override Flash Sale supaya "Produk Baru" tetap akurat by waktu.
  if (newFilter) {
    return { createdAt: "desc" };
  }
  // Default sort: BOOST Flash Sale aktif ke top. Prisma sort
  // `flashSaleEndsAt asc nulls last` → produk dengan endsAt set
  // (Flash Sale aktif maupun expired) di-rank lebih awal, di-sort
  // by earliest expiry first. Produk tanpa endsAt fallback ke
  // createdAt desc.
  //
  // Rationale: Flutter homepage fetch /api/products default + filter
  // Flash Sale eligible client-side. Tanpa boost, Flash Sale products
  // bisa terkubur di posisi >48 kalau bukan produk terbaru.
  return [
    { flashSaleEndsAt: { sort: "asc", nulls: "last" } },
    { createdAt: "desc" },
  ];
}

export async function getProducts(opts?: {
  category?: string;
  brand?: string;
  search?: string;
  take?: number;
  skip?: number;
  newFilter?: NewProductFilter;
  popularFilter?: PopularFilter;
  randomSeed?: string;
  excludeIds?: string[];
  hasPriceOnly?: boolean;
  inStockOnly?: boolean;
  withImageOnly?: boolean;
  viewerId?: string | null;
}): Promise<StoreProduct[]> {
  const {
    category,
    brand,
    search,
    take,
    skip,
    newFilter,
    popularFilter,
    randomSeed,
    excludeIds,
    hasPriceOnly,
    inStockOnly,
    withImageOnly,
    viewerId,
  } = opts ?? {};
  const createdAtCutoff = newProductCutoff(newFilter);
  const where = buildProductWhere({
    category,
    brand,
    search,
    createdAtCutoff,
    excludeIds,
    hasPriceOnly,
    inStockOnly,
    withImageOnly,
  });

  try {
    if (popularFilter === "most-searched") {
      const productIds = await getMostSearchedProductIds({
        productWhere: where,
        take,
        skip,
      });
      if (!productIds.length) return [];

      const order = new Map(productIds.map((id, index) => [id, index]));
      const products = await prisma.product.findMany({
        where: { id: { in: productIds } },
        include: getProductListInclude(),
      });

      return withProductListMeta(
        products
          .sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0))
          .map(mapProductListRecord),
        viewerId
      );
    }

    if (isOrderDrivenPopularFilter(popularFilter)) {
      const productIds =
        popularFilter === "trending"
          ? await getTrendingProductIds({ productWhere: where, take, skip })
          : await getBestSellerProductIds({ productWhere: where, take, skip });

      if (!productIds.length) return [];

      const order = new Map(productIds.map((id, index) => [id, index]));
      const products = await prisma.product.findMany({
        where: { id: { in: productIds } },
        include: getProductListInclude(),
      });

      return withProductListMeta(
        products
          .sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0))
          .map(mapProductListRecord),
        viewerId
      );
    }

    if (
      randomSeed &&
      !category &&
      !brand &&
      !search &&
      !newFilter &&
      !popularFilter &&
      !excludeIds?.length &&
      !hasPriceOnly &&
      !inStockOnly &&
      !withImageOnly
    ) {
      const idRows = await prisma.$queryRaw<{ id: string }[]>`
        SELECT "id"
        FROM "Product"
        WHERE "isActive" = true
        ORDER BY md5("id" || ${randomSeed}) ASC
        LIMIT ${take ?? 24}
        OFFSET ${skip ?? 0}
      `;
      const ids = idRows.map((row) => row.id);
      if (!ids.length) return [];

      const order = new Map(ids.map((id, index) => [id, index]));
      const products = await prisma.product.findMany({
        where: { id: { in: ids } },
        include: getProductListInclude(),
      });

      return withProductListMeta(
        products
          .sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0))
          .map(mapProductListRecord),
        viewerId
      );
    }

    const listWhere =
      popularFilter === "highest-rating"
        ? withAnd(where, { avgRating: { gt: 0 }, reviewCount: { gt: 0 } })
        : where;

    const products = await prisma.product.findMany({
      where: listWhere,
      orderBy: buildOrderBy(newFilter, popularFilter),
      take,
      skip,
      include: getProductListInclude(),
    });

    if (!products.length) {
      if (category || brand || search || newFilter || popularFilter) return [];
      return withProductListMeta(sampleProducts, viewerId);
    }

    return withProductListMeta(products.map(mapProductListRecord), viewerId);
  } catch {
    if (randomSeed) return [];
    if (category || brand || search || newFilter || popularFilter) return [];
    return withVoucherPreviews(sampleProducts, viewerId);
  }
}

export async function getProductsCount(opts?: {
  category?: string;
  brand?: string;
  search?: string;
  newFilter?: NewProductFilter;
  popularFilter?: PopularFilter;
  excludeIds?: string[];
  hasPriceOnly?: boolean;
  inStockOnly?: boolean;
  withImageOnly?: boolean;
}): Promise<number> {
  const {
    category,
    brand,
    search,
    newFilter,
    popularFilter,
    excludeIds,
    hasPriceOnly,
    inStockOnly,
    withImageOnly,
  } = opts ?? {};
  const createdAtCutoff = newProductCutoff(newFilter);
  const where = buildProductWhere({
    category,
    brand,
    search,
    createdAtCutoff,
    excludeIds,
    hasPriceOnly,
    inStockOnly,
    withImageOnly,
  });

  try {
    if (popularFilter === "most-searched") {
      const productIds = await getMostSearchedProductIds({
        productWhere: where,
      });
      return productIds.length;
    }

    if (isOrderDrivenPopularFilter(popularFilter)) {
      const productIds =
        popularFilter === "trending"
          ? await getTrendingProductIds({ productWhere: where })
          : await getBestSellerProductIds({ productWhere: where });
      return productIds.length;
    }

    const countWhere =
      popularFilter === "highest-rating"
        ? withAnd(where, { avgRating: { gt: 0 }, reviewCount: { gt: 0 } })
        : where;

    return await prisma.product.count({
      where: countWhere,
    });
  } catch {
    return 0;
  }
}

function buildProductWhere({
  category,
  brand,
  search,
  createdAtCutoff,
  excludeIds,
  hasPriceOnly,
  inStockOnly,
  withImageOnly,
}: {
  category?: string;
  brand?: string;
  search?: string;
  createdAtCutoff?: Date | null;
  excludeIds?: string[];
  hasPriceOnly?: boolean;
  inStockOnly?: boolean;
  withImageOnly?: boolean;
}): Prisma.ProductWhereInput {
  const and: Prisma.ProductWhereInput[] = [];

  if (withImageOnly) {
    and.push({ imageUrl: { not: null } }, { imageUrl: { not: "" } });
  }

  if (inStockOnly) {
    and.push({
      OR: [
        { hasVariants: false, stock: { gt: 0 } },
        {
          hasVariants: true,
          variants: {
            some: { deletedAt: null, isActive: true, stock: { gt: 0 } },
          },
        },
      ],
    });
  }

  if (hasPriceOnly) {
    and.push({
      OR: [
        { hasVariants: false, price: { gt: 0 } },
        {
          hasVariants: true,
          variants: {
            some: { deletedAt: null, isActive: true, price: { gt: 0 } },
          },
        },
      ],
    });
  }

  return {
    isActive: true,
    ...(category ? { category: { slug: category } } : {}),
    ...(brand ? { brand: { slug: brand, isActive: true } } : {}),
    ...(search ? { name: { contains: search, mode: "insensitive" } } : {}),
    ...(createdAtCutoff
      ? { createdAt: { gte: createdAtCutoff, lte: new Date() } }
      : {}),
    ...(excludeIds?.length ? { id: { notIn: excludeIds } } : {}),
    ...(and.length ? { AND: and } : {}),
  };
}

export async function getProductBySlug(
  slug: string,
  opts?: { viewerId?: string | null }
): Promise<StoreProduct | null> {
  const viewerId = opts?.viewerId;
  try {
    // Cari by slug dulu — kalau tidak ada, fallback by id. Berguna untuk
    // legacy cart items yang belum punya slug (tersimpan productId only),
    // atau deep-link by id.
    // Include active Promo Toko items untuk apply pricing.
    const discountItemsInclude = {
      discountItems: {
        where: {
          isItemActive: true,
          discount: {
            isActive: true,
            startsAt: { lte: new Date() },
            endsAt: { gt: new Date() },
          },
        },
        select: {
          variantId: true,
          discountedPrice: true,
          discount: { select: { endsAt: true } },
        },
      },
    };
    let p = await prisma.product.findUnique({
      where: { slug },
      include: {
        ...variantInclude,
        ...discountItemsInclude,
        category: { select: { id: true, slug: true } },
      },
    });
    if (!p) {
      p = await prisma.product.findUnique({
        where: { id: slug },
        include: {
          ...variantInclude,
          ...discountItemsInclude,
          category: { select: { id: true, slug: true } },
        },
      });
    }
    if (!p) return sampleProducts.find((item) => item.slug === slug) ?? null;

    if (p.hasVariants && p.variants.length > 0) {
      const activeVariants = p.variants.filter((v) => v.isActive);
      const prices = activeVariants.map((v) => v.price);
      const totalStock = activeVariants.reduce((s, v) => s + v.stock, 0);

      // Apply pricing per-variant: kalau ada Promo Toko match (per variantId)
      // atau Flash Sale (ratio dari product level), pakai harga terendah.
      const effectiveVariantPrices = activeVariants.map((v) => {
        const variantPromoItems = (p.discountItems ?? [])
          .filter((it) => it.variantId === v.id)
          .map((it) => ({
            discountedPrice: it.discountedPrice,
            endsAt: it.discount.endsAt,
          }));
        const discount = resolveActiveDiscount(
          v.price,
          flashSaleForVariant(p.price, p.discountPrice, p.flashSaleEndsAt, v.price),
          variantPromoItems,
        );
        return discount ? discount.effectivePrice : v.price;
      });
      const minEffective = effectiveVariantPrices.length
        ? Math.min(...effectiveVariantPrices)
        : p.price;
      const minBase = prices.length ? Math.min(...prices) : p.price;

      const product: StoreProduct = {
        id: p.id,
        name: p.name,
        slug: p.slug,
        description: p.description,
        price: minBase,
        discountPrice: minEffective < minBase ? minEffective : null,
        memberPrice: p.memberPrice,
        stock: totalStock,
        weightGram: normalizeProductWeight(p.name, p.slug, p.weightGram),
        imageUrl: p.imageUrl,
        gallery: p.gallery ?? [],
        hasVariants: true,
        avgRating: p.avgRating,
        reviewCount: p.reviewCount,
        categoryId: p.category?.id ?? null,
        categorySlug: p.category?.slug ?? null,
        voucherPreview: null,
        shippingVoucherPreview: null,
        variantAttrs: p.variantAttrs as unknown as StoreVariantAttribute[],
        variants: p.variants as unknown as StoreProductVariant[],
        flashSaleEndsAt: p.flashSaleEndsAt?.toISOString() ?? null,
      };
      const [withPreview] = await withVoucherPreviews([product], viewerId);
      return withPreview;
    }

    // Single product (no variants) — apply pricing langsung.
    const promoItems = (p.discountItems ?? [])
      .filter((it) => it.variantId === null)
      .map((it) => ({
        discountedPrice: it.discountedPrice,
        endsAt: it.discount.endsAt,
      }));
    const discount = resolveActiveDiscount(
      p.price,
      { discountPrice: p.discountPrice, endsAt: p.flashSaleEndsAt },
      promoItems,
    );
    const effectiveDiscountPrice = discount ? discount.effectivePrice : null;
    const effectiveFlashSaleEndsAt =
      discount?.source === "FLASH_SALE"
        ? p.flashSaleEndsAt?.toISOString() ?? null
        : null;

    const product = {
      id: p.id,
      name: p.name,
      slug: p.slug,
      description: p.description,
      price: p.price,
      discountPrice: effectiveDiscountPrice,
      memberPrice: p.memberPrice,
      stock: p.stock,
      weightGram: normalizeProductWeight(p.name, p.slug, p.weightGram),
      imageUrl: p.imageUrl,
      gallery: p.gallery ?? [],
      hasVariants: false,
      avgRating: p.avgRating,
      reviewCount: p.reviewCount,
      categoryId: p.category?.id ?? null,
      categorySlug: p.category?.slug ?? null,
      flashSaleEndsAt: effectiveFlashSaleEndsAt,
    };
    const [withPreview] = await withVoucherPreviews([product], viewerId);
    return withPreview;
  } catch {
    const sample = sampleProducts.find((item) => item.slug === slug);
    if (!sample) return null;
    const [withPreview] = await withVoucherPreviews([sample], viewerId);
    return withPreview;
  }
}
