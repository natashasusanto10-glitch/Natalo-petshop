import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

/**
 * GET /api/admin/dashboard-stats
 *
 * Stats untuk dashboard admin app (flutter_admin/ + web admin dashboard).
 *
 * Returns:
 * - `ordersToday` — count Order yang createdAt hari ini (timezone Asia/Jakarta)
 * - `omzetToday` — sum total dari Order PAID hari ini
 * - `pendingShipment` — count Order status=PAID atau PROCESSING (perlu dikirim)
 * - `lowStockCount` — count Product dengan totalStock <= 5 dan isActive
 *
 * Dihitung di server-side dengan Prisma aggregations supaya cepat & akurat.
 */
export async function GET() {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json(
      { error: "Unauthorized — admin session required" },
      { status: 401 },
    );
  }

  // Asia/Jakarta = UTC+7. Hari ini = window 00:00–24:00 Jakarta time.
  // Untuk simplicity, kita pakai UTC offset langsung (tidak handle DST karena
  // Indonesia tidak ada DST).
  const now = new Date();
  const jakartaOffsetMs = 7 * 60 * 60 * 1000;
  const jakartaNow = new Date(now.getTime() + jakartaOffsetMs);
  const startOfDayJakarta = new Date(
    Date.UTC(
      jakartaNow.getUTCFullYear(),
      jakartaNow.getUTCMonth(),
      jakartaNow.getUTCDate(),
    ) -
      jakartaOffsetMs,
  );
  const endOfDayJakarta = new Date(
    startOfDayJakarta.getTime() + 24 * 60 * 60 * 1000,
  );

  const [ordersTodayCount, omzetTodayAgg, pendingShipCount, lowStockCount] =
    await Promise.all([
      prisma.order.count({
        where: {
          createdAt: { gte: startOfDayJakarta, lt: endOfDayJakarta },
        },
      }),
      prisma.order.aggregate({
        where: {
          createdAt: { gte: startOfDayJakarta, lt: endOfDayJakarta },
          status: { in: ["PAID", "PROCESSING", "SHIPPED", "DELIVERED"] },
        },
        _sum: { total: true },
      }),
      prisma.order.count({
        where: {
          status: { in: ["PAID", "PROCESSING"] },
        },
      }),
      prisma.product.count({
        where: {
          isActive: true,
          stock: { lte: 5 },
        },
      }),
    ]);

  return NextResponse.json({
    ordersToday: ordersTodayCount,
    omzetToday: omzetTodayAgg._sum.total ?? 0,
    pendingShipment: pendingShipCount,
    lowStockCount,
  });
}
