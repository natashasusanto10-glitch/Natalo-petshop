/**
 * Performa Promosi analytics — hitung metrik order yang related dengan
 * produk yang sedang ATAU pernah masuk promo (Flash Sale + Promo Toko)
 * dalam periode tertentu.
 *
 * 4 metrik utama (match Shopee Seller Performa Promosi):
 *  - Penjualan (Rp)   : total revenue dari item promo
 *  - Pesanan          : count distinct orders yang include item promo
 *  - Jumlah Terjual   : sum quantity item promo
 *  - Pembeli          : count distinct user yang beli item promo
 *
 * Compared to previous period (same duration sebelum start) untuk
 * delta % (vs 7 hari terakhir, vs 30 hari terakhir, dsb.).
 *
 * Pendekatan: query orders di periode → cross-reference dengan
 * produk yang sedang/pernah masuk promo di periode itu. Produk dianggap
 * "in promo" kalau periode promo (Flash Sale flashSaleEndsAt /
 * ProductDiscount startsAt-endsAt) overlap dengan order.createdAt.
 *
 * NOTE: ini approximation — kita identify "promo product" by checking
 * apakah ada promo yang ACTIVE saat order dibuat. Lebih akurat daripada
 * snapshot-based, tapi tidak perfect (admin yang ubah promo periode
 * setelahnya bisa miss-classify historical orders).
 */
import { prisma } from "@/lib/prisma";

export interface PerformaMetrics {
  penjualan: number; // Rp
  pesanan: number; // count distinct orders
  jumlahTerjual: number; // sum quantity
  pembeli: number; // count distinct users
}

export interface PerformaMetricsWithDelta {
  current: PerformaMetrics;
  previous: PerformaMetrics;
  deltaPercent: {
    penjualan: number | null;
    pesanan: number | null;
    jumlahTerjual: number | null;
    pembeli: number | null;
  };
}

/** Hitung % delta. Null kalau previous = 0 (tidak ada baseline). */
function calcDelta(current: number, previous: number): number | null {
  if (previous === 0) return current > 0 ? null : 0;
  return Math.round(((current - previous) / previous) * 100);
}

/**
 * Get produk IDs yang ada di promo aktif dalam periode tertentu.
 * Combined Flash Sale + Promo Toko.
 *
 * Pattern: kalau salah satu kondisi true → produk dianggap "in promo"
 * di periode itu:
 *  - flashSaleEndsAt > start (Flash Sale aktif overlap periode)
 *  - ProductDiscount dengan startsAt < end AND endsAt > start
 */
async function getPromoProductIdsInPeriod(
  start: Date,
  end: Date,
): Promise<Set<string>> {
  const promoIds = new Set<string>();

  // Flash Sale: produk dengan flashSaleEndsAt > start (Flash Sale berakhir
  // setelah periode mulai → mungkin overlap)
  const flashProducts = await prisma.product.findMany({
    where: {
      flashSaleEndsAt: { gt: start },
      // Loose filter: Flash Sale ended any time after periode start → counts
    },
    select: { id: true },
  });
  for (const p of flashProducts) promoIds.add(p.id);

  // Promo Toko: ProductDiscount dengan periode yang overlap (start-end)
  const promoTokoItems = await prisma.productDiscountItem.findMany({
    where: {
      discount: {
        startsAt: { lt: end },
        endsAt: { gt: start },
      },
    },
    select: { productId: true },
  });
  for (const item of promoTokoItems) promoIds.add(item.productId);

  return promoIds;
}

/**
 * Compute metrik untuk satu periode.
 *
 * Note: pakai status order yang menghasilkan revenue:
 *  - PAID, PROCESSING, SHIPPED, DELIVERED (semua yang sudah dibayar)
 *  - Exclude: PENDING (belum bayar), CANCELLED, REFUNDED
 */
async function computeMetricsForPeriod(
  start: Date,
  end: Date,
  promoProductIds: Set<string>,
): Promise<PerformaMetrics> {
  if (promoProductIds.size === 0) {
    return { penjualan: 0, pesanan: 0, jumlahTerjual: 0, pembeli: 0 };
  }

  const productIdsList = Array.from(promoProductIds);

  // Query order items dari produk promo, di periode, status revenue-eligible
  const orderItems = await prisma.orderItem.findMany({
    where: {
      productId: { in: productIdsList },
      order: {
        createdAt: { gte: start, lt: end },
        status: { in: ["PAID", "PROCESSING", "SHIPPED", "DELIVERED"] },
      },
    },
    select: {
      productId: true,
      price: true,
      quantity: true,
      orderId: true,
      order: {
        select: { userId: true },
      },
    },
  });

  if (orderItems.length === 0) {
    return { penjualan: 0, pesanan: 0, jumlahTerjual: 0, pembeli: 0 };
  }

  const penjualan = orderItems.reduce(
    (sum, item) => sum + item.price * item.quantity,
    0,
  );
  const jumlahTerjual = orderItems.reduce(
    (sum, item) => sum + item.quantity,
    0,
  );
  const uniqueOrders = new Set(orderItems.map((it) => it.orderId));
  const uniqueUsers = new Set(
    orderItems.map((it) => it.order.userId).filter((id): id is string => !!id),
  );

  return {
    penjualan,
    pesanan: uniqueOrders.size,
    jumlahTerjual,
    pembeli: uniqueUsers.size,
  };
}

/**
 * Get Performa Promosi metrics + delta vs previous period.
 *
 * @param start  Mulai periode (inclusive)
 * @param end    Akhir periode (exclusive)
 * @returns Metrik current + previous + delta %
 */
export async function getPerformaMetrics(
  start: Date,
  end: Date,
): Promise<PerformaMetricsWithDelta> {
  // Previous period: same duration sebelum start
  const duration = end.getTime() - start.getTime();
  const prevStart = new Date(start.getTime() - duration);
  const prevEnd = new Date(start);

  // Identify produk yang ada di promo di tiap periode (current + previous).
  // Concurrent fetch.
  const [currentPromoIds, previousPromoIds] = await Promise.all([
    getPromoProductIdsInPeriod(start, end),
    getPromoProductIdsInPeriod(prevStart, prevEnd),
  ]);

  // Compute metrics untuk tiap periode concurrent
  const [current, previous] = await Promise.all([
    computeMetricsForPeriod(start, end, currentPromoIds),
    computeMetricsForPeriod(prevStart, prevEnd, previousPromoIds),
  ]);

  return {
    current,
    previous,
    deltaPercent: {
      penjualan: calcDelta(current.penjualan, previous.penjualan),
      pesanan: calcDelta(current.pesanan, previous.pesanan),
      jumlahTerjual: calcDelta(current.jumlahTerjual, previous.jumlahTerjual),
      pembeli: calcDelta(current.pembeli, previous.pembeli),
    },
  };
}
