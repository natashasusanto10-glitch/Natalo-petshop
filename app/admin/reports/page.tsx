import { prisma } from "@/lib/prisma";
import { requireAdminSession } from "@/lib/session-guards";
import { ReportsView } from "@/components/admin/views/ReportsView";
import { jakartaMonthRange } from "@/lib/format";
import type { Prisma } from "@prisma/client";

export default async function AdminReportsPage() {
  await requireAdminSession();

  const now = new Date();
  const thisMonth = jakartaMonthRange(0, now);
  const lastMonth = jakartaMonthRange(1, now);
  // Match dashboard revenue: paid orders, excluding cancellations/refunds.
  const validSale = {
    paymentStatus: "PAID",
    status: { notIn: ["CANCELLED", "REFUNDED"] },
  } satisfies Prisma.OrderWhereInput;

  const [
    revenueThisMonth,
    revenueLastMonth,
    ordersThisMonth,
    ordersLastMonth,
    topProductTotals,
    ordersByStatus,
  ] = await Promise.all([
    prisma.order.aggregate({
      _sum: { total: true },
      where: {
        ...validSale,
        createdAt: { gte: thisMonth.start, lt: thisMonth.end },
      },
    }),
    prisma.order.aggregate({
      _sum: { total: true },
      where: {
        ...validSale,
        createdAt: { gte: lastMonth.start, lt: lastMonth.end },
      },
    }),
    prisma.order.count({
      where: { createdAt: { gte: thisMonth.start, lt: thisMonth.end } },
    }),
    prisma.order.count({
      where: { createdAt: { gte: lastMonth.start, lt: lastMonth.end } },
    }),
    prisma.orderItem.groupBy({
      by: ["productId"],
      where: { order: validSale },
      _sum: { quantity: true },
      orderBy: [{ _sum: { quantity: "desc" } }, { productId: "asc" }],
      take: 10,
    }),
    prisma.order.groupBy({
      by: ["status"],
      _count: true,
    }),
  ]);

  const products = topProductTotals.length
    ? await prisma.product.findMany({
        where: { id: { in: topProductTotals.map((item) => item.productId) } },
        select: { id: true, name: true },
      })
    : [];
  const names = new Map(products.map((product) => [product.id, product.name]));
  const topProducts = topProductTotals.map((item) => ({
    id: item.productId,
    name: names.get(item.productId) ?? "Produk tidak tersedia",
    quantity: item._sum.quantity ?? 0,
  }));

  const thisMonthRevenue = revenueThisMonth._sum.total ?? 0;
  const lastMonthRevenue = revenueLastMonth._sum.total ?? 0;
  const revenueGrowth =
    lastMonthRevenue > 0
      ? Math.round(
          ((thisMonthRevenue - lastMonthRevenue) / lastMonthRevenue) * 100
        )
      : null;

  const statusMap: Record<string, number> = {};
  for (const s of ordersByStatus) statusMap[s.status] = s._count;

  const monthName = now.toLocaleDateString("id-ID", {
    timeZone: "Asia/Jakarta",
    month: "long",
    year: "numeric",
  });

  return (
    <ReportsView
      monthName={monthName}
      thisMonthRevenue={thisMonthRevenue}
      lastMonthRevenue={lastMonthRevenue}
      revenueGrowth={revenueGrowth}
      ordersThisMonth={ordersThisMonth}
      ordersLastMonth={ordersLastMonth}
      topProducts={topProducts}
      statusMap={statusMap}
    />
  );
}
