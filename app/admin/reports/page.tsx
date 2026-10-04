import { prisma } from "@/lib/prisma";
import { requireAdminSession } from "@/lib/session-guards";
import { ReportsView } from "@/components/admin/views/ReportsView";

export default async function AdminReportsPage() {
  await requireAdminSession();

  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const startOfLastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const endOfLastMonth = new Date(
    now.getFullYear(),
    now.getMonth(),
    0,
    23,
    59,
    59
  );

  const [
    revenueThisMonth,
    revenueLastMonth,
    ordersThisMonth,
    ordersLastMonth,
    topProducts,
    ordersByStatus,
  ] = await Promise.all([
    prisma.order.aggregate({
      _sum: { total: true },
      where: { paymentStatus: "PAID", createdAt: { gte: startOfMonth } },
    }),
    prisma.order.aggregate({
      _sum: { total: true },
      where: {
        paymentStatus: "PAID",
        createdAt: { gte: startOfLastMonth, lte: endOfLastMonth },
      },
    }),
    prisma.order.count({ where: { createdAt: { gte: startOfMonth } } }),
    prisma.order.count({
      where: { createdAt: { gte: startOfLastMonth, lte: endOfLastMonth } },
    }),
    prisma.orderItem.groupBy({
      by: ["name"],
      _sum: { quantity: true },
      orderBy: { _sum: { quantity: "desc" } },
      take: 10,
    }),
    prisma.order.groupBy({
      by: ["status"],
      _count: true,
    }),
  ]);

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
