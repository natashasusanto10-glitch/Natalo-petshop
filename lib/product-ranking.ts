import type { OrderStatus, Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";

/**
 * Ranking + promo helpers dipakai BERSAMA oleh lib/products.ts dan
 * lib/search.ts. Modul terpisah supaya tidak ada circular import
 * (lib/products.ts sudah import dari lib/search.ts).
 *
 * Fungsi murni di atas, wrapper yang menyentuh DB di bawah.
 */

export const VALID_SALES_ORDER_STATUSES: OrderStatus[] = [
  "PAID",
  "PROCESSING",
  "READY_FOR_PICKUP",
  "SHIPPED",
  "DELIVERED",
];

export const TRENDING_WINDOW_DAYS = 14;
export const WIB_OFFSET_MS = 7 * 60 * 60 * 1000;

export function wibDateKey(date: Date) {
  return new Date(date.getTime() + WIB_OFFSET_MS).toISOString().slice(0, 10);
}

export function toAndArray(and: Prisma.ProductWhereInput["AND"]) {
  if (!and) return [];
  return Array.isArray(and) ? and : [and];
}

export function withAnd(
  where: Prisma.ProductWhereInput,
  condition: Prisma.ProductWhereInput,
): Prisma.ProductWhereInput {
  return {
    ...where,
    AND: [...toAndArray(where.AND), condition],
  };
}

/** Produk hanya layak masuk ranking kalau benar-benar bisa dibeli. */
export function productRankWhere(
  where: Prisma.ProductWhereInput,
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

/** Flash Sale aktif ATAU Promo Toko aktif pada `now`. */
export function discountOnlyWhere(now: Date = new Date()): Prisma.ProductWhereInput {
  return {
    OR: [
      // Flash Sale aktif: punya discountPrice + flashSaleEndsAt future
      {
        AND: [{ discountPrice: { not: null } }, { flashSaleEndsAt: { gt: now } }],
      },
      // Punya ProductDiscountItem aktif (Promo Toko)
      {
        discountItems: {
          some: {
            isItemActive: true,
            discount: {
              isActive: true,
              startsAt: { lte: now },
              endsAt: { gt: now },
            },
          },
        },
      },
    ],
  };
}

export type TrendingRow = {
  productId: string;
  quantity: number;
  order: {
    id: string;
    userId: string | null;
    customerEmail: string | null;
    customerPhone: string | null;
    createdAt: Date;
  };
};

/**
 * Inti skoring trending — MURNI, tanpa DB, supaya bisa di-unit-test.
 * Skor = totalSold*0.5 + pembeli unik*0.3 + hari-beli unik*0.2,
 * hanya produk yang dibeli minimal 2 hari berbeda (anti-spike).
 */
export function computeTrendingRanking(
  rows: TrendingRow[],
  { take, skip }: { take?: number; skip?: number } = {},
): string[] {
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
      if (b.trendingScore !== a.trendingScore)
        return b.trendingScore - a.trendingScore;
      if (b.totalSold !== a.totalSold) return b.totalSold - a.totalSold;
      return b.purchaseFrequencyDays - a.purchaseFrequencyDays;
    })
    .slice(skip ?? 0, typeof take === "number" ? (skip ?? 0) + take : undefined)
    .map((item) => item.productId);
}

/** Urutan produk by penjualan asli (agregasi OrderItem). */
export async function getBestSellerProductIds({
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

/** Urutan produk by skor trending 14 hari terakhir. */
export async function getTrendingProductIds({
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

  return computeTrendingRanking(rows, { take, skip });
}
