import { prisma } from "@/lib/prisma";
import {
  attachPublicProductVoucherPreviews,
  type ProductVoucherPreview,
} from "@/lib/product-vouchers";
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
  categoryId?: string | null;
  categorySlug?: string | null;
  voucherPreview?: ProductVoucherPreview | null;
  // hanya diisi oleh getProductBySlug
  variantAttrs?: StoreVariantAttribute[];
  variants?: StoreProductVariant[];
};

function normalizeProductWeight(name: string, slug: string, weightGram: number) {
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

const productListInclude = {
  category: { select: { id: true, slug: true } },
  variants: {
    where: { deletedAt: null, isActive: true },
    select: { price: true, stock: true },
  },
} satisfies Prisma.ProductInclude;

type ProductListRecord = Prisma.ProductGetPayload<{ include: typeof productListInclude }>;

function mapProductListRecord(p: ProductListRecord): StoreProduct {
  if (p.hasVariants && p.variants.length > 0) {
    const prices = p.variants.map((v) => v.price);
    const totalStock = p.variants.reduce((s, v) => s + v.stock, 0);
    return {
      id: p.id,
      name: p.name,
      slug: p.slug,
      description: p.description,
      price: Math.min(...prices),
      discountPrice: null,
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
    };
  }

  return {
    id: p.id,
    name: p.name,
    slug: p.slug,
    description: p.description,
    price: p.price,
    discountPrice: p.discountPrice,
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
  };
}

async function withVoucherPreviews(products: StoreProduct[]) {
  return attachPublicProductVoucherPreviews(products);
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
  condition: Prisma.ProductWhereInput,
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
      wibDate.getUTCDate(),
    ) - WIB_OFFSET_MS,
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
      wibDate.getUTCDate(),
    ) - WIB_OFFSET_MS,
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
  if (filter === "this-month" || filter === "last-30-days" || filter === "newest") {
    return daysAgo(now, NEW_PRODUCT_WINDOW_DAYS);
  }
  return null;
}

function wibDateKey(date: Date) {
  return new Date(date.getTime() + WIB_OFFSET_MS).toISOString().slice(0, 10);
}

function productRankWhere(where: Prisma.ProductWhereInput): Prisma.ProductWhereInput {
  return withAnd(where, {
    OR: [
      { hasVariants: false, price: { gt: 0 }, stock: { gt: 0 } },
      {
        hasVariants: true,
        variants: {
          some: { deletedAt: null, isActive: true, price: { gt: 0 }, stock: { gt: 0 } },
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
    const productStats =
      stats.get(row.productId) ??
      { totalSold: 0, buyerIds: new Set<string>(), purchaseDays: new Set<string>() };
    productStats.totalSold += row.quantity;
    productStats.buyerIds.add(
      row.order.userId ??
        row.order.customerEmail ??
        row.order.customerPhone ??
        `order:${row.order.id}`,
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
      if (b.trendingScore !== a.trendingScore) return b.trendingScore - a.trendingScore;
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
        }),
      ),
      select: { id: true },
      take: 24,
    });

    for (const product of matches) {
      scores.set(product.id, (scores.get(product.id) ?? 0) + row._count.keyword);
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
  popularFilter?: PopularFilter,
): Prisma.ProductOrderByWithRelationInput | Prisma.ProductOrderByWithRelationInput[] {
  // Popular filter has priority over new filter for ordering
  if (popularFilter === "highest-rating") {
    return [{ avgRating: "desc" }, { reviewCount: "desc" }];
  }
  // Default & new filter sort
  return { createdAt: "desc" };
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
      const productIds = await getMostSearchedProductIds({ productWhere: where, take, skip });
      if (!productIds.length) return [];

      const order = new Map(productIds.map((id, index) => [id, index]));
      const products = await prisma.product.findMany({
        where: { id: { in: productIds } },
        include: productListInclude,
      });

      return withVoucherPreviews(products
        .sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0))
        .map(mapProductListRecord));
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
        include: productListInclude,
      });

      return withVoucherPreviews(products
        .sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0))
        .map(mapProductListRecord));
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
        include: productListInclude,
      });

      return withVoucherPreviews(products
        .sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0))
        .map(mapProductListRecord));
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
      include: productListInclude,
    });

    if (!products.length) {
      if (category || brand || search || newFilter || popularFilter) return [];
      return withVoucherPreviews(sampleProducts);
    }

    return withVoucherPreviews(products.map(mapProductListRecord));
  } catch {
    if (randomSeed) return [];
    if (category || brand || search || newFilter || popularFilter) return [];
    return withVoucherPreviews(sampleProducts);
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
      const productIds = await getMostSearchedProductIds({ productWhere: where });
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
    ...(createdAtCutoff ? { createdAt: { gte: createdAtCutoff, lte: new Date() } } : {}),
    ...(excludeIds?.length ? { id: { notIn: excludeIds } } : {}),
    ...(and.length ? { AND: and } : {}),
  };
}

export async function getProductBySlug(slug: string): Promise<StoreProduct | null> {
  try {
    // Cari by slug dulu — kalau tidak ada, fallback by id. Berguna untuk
    // legacy cart items yang belum punya slug (tersimpan productId only),
    // atau deep-link by id.
    let p = await prisma.product.findUnique({
      where: { slug },
      include: { ...variantInclude, category: { select: { id: true, slug: true } } },
    });
    if (!p) {
      p = await prisma.product.findUnique({
        where: { id: slug },
        include: { ...variantInclude, category: { select: { id: true, slug: true } } },
      });
    }
    if (!p) return sampleProducts.find((item) => item.slug === slug) ?? null;

    if (p.hasVariants && p.variants.length > 0) {
      const activeVariants = p.variants.filter((v) => v.isActive);
      const prices = activeVariants.map((v) => v.price);
      const totalStock = activeVariants.reduce((s, v) => s + v.stock, 0);
      const product: StoreProduct = {
        id: p.id,
        name: p.name,
        slug: p.slug,
        description: p.description,
        price: prices.length ? Math.min(...prices) : p.price,
        discountPrice: null,
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
        variantAttrs: p.variantAttrs as unknown as StoreVariantAttribute[],
        variants: p.variants as unknown as StoreProductVariant[],
      };
      const [withPreview] = await withVoucherPreviews([product]);
      return withPreview;
    }

    const product = {
      id: p.id,
      name: p.name,
      slug: p.slug,
      description: p.description,
      price: p.price,
      discountPrice: p.discountPrice,
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
    };
    const [withPreview] = await withVoucherPreviews([product]);
    return withPreview;
  } catch {
    const sample = sampleProducts.find((item) => item.slug === slug);
    if (!sample) return null;
    const [withPreview] = await withVoucherPreviews([sample]);
    return withPreview;
  }
}
