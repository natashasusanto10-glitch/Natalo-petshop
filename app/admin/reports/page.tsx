import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";

export default async function AdminReportsPage() {
  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const startOfLastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const endOfLastMonth = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);

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
      ? (((thisMonthRevenue - lastMonthRevenue) / lastMonthRevenue) * 100).toFixed(1)
      : null;

  const statusMap: Record<string, number> = {};
  for (const s of ordersByStatus) statusMap[s.status] = s._count;

  const monthName = now.toLocaleDateString("id-ID", { month: "long", year: "numeric" });

  return (
    <div className="mx-auto max-w-4xl px-4 py-6 lg:py-10">
      <div>
        <h1 className="text-2xl font-black tracking-tight text-zinc-950 lg:text-3xl">Laporan</h1>
        <p className="mt-1 text-sm text-zinc-500">Ringkasan performa toko — {monthName}.</p>
      </div>

      {/* This month stats */}
      <div className="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <div className="rounded-2xl border border-zinc-100 bg-white p-4">
          <p className="text-xs font-semibold text-zinc-500">Pendapatan Bulan Ini</p>
          <p className="mt-2 text-lg font-black text-orange-600">{formatRupiah(thisMonthRevenue)}</p>
          {revenueGrowth !== null && (
            <p className={`mt-1 text-xs font-semibold ${parseFloat(revenueGrowth) >= 0 ? "text-emerald-600" : "text-red-500"}`}>
              {parseFloat(revenueGrowth) >= 0 ? "▲" : "▼"} {Math.abs(parseFloat(revenueGrowth))}% vs bulan lalu
            </p>
          )}
        </div>
        <div className="rounded-2xl border border-zinc-100 bg-white p-4">
          <p className="text-xs font-semibold text-zinc-500">Pendapatan Bulan Lalu</p>
          <p className="mt-2 text-lg font-black text-zinc-700">{formatRupiah(lastMonthRevenue)}</p>
        </div>
        <div className="rounded-2xl border border-zinc-100 bg-white p-4">
          <p className="text-xs font-semibold text-zinc-500">Order Bulan Ini</p>
          <p className="mt-2 text-2xl font-black text-blue-600">{ordersThisMonth}</p>
        </div>
        <div className="rounded-2xl border border-zinc-100 bg-white p-4">
          <p className="text-xs font-semibold text-zinc-500">Order Bulan Lalu</p>
          <p className="mt-2 text-2xl font-black text-zinc-700">{ordersLastMonth}</p>
        </div>
      </div>

      <div className="mt-5 grid gap-5 lg:grid-cols-2">
        {/* Top products */}
        <section className="rounded-3xl border border-zinc-200 bg-white p-5">
          <h2 className="font-bold text-zinc-950">Produk Terlaris</h2>
          <div className="mt-4 space-y-2">
            {topProducts.length > 0 ? (
              topProducts.map((item, i) => (
                <div key={item.name} className="flex items-center gap-3 rounded-xl bg-zinc-50 px-4 py-3">
                  <span className="w-6 shrink-0 text-center text-xs font-black text-zinc-400">{i + 1}</span>
                  <p className="flex-1 truncate text-sm font-semibold text-zinc-900">{item.name}</p>
                  <span className="shrink-0 rounded-full bg-orange-100 px-2.5 py-1 text-xs font-bold text-orange-700">
                    {item._sum.quantity ?? 0}x
                  </span>
                </div>
              ))
            ) : (
              <p className="text-sm text-zinc-500">Belum ada data.</p>
            )}
          </div>
        </section>

        {/* Order by status */}
        <section className="rounded-3xl border border-zinc-200 bg-white p-5">
          <h2 className="font-bold text-zinc-950">Distribusi Status Order</h2>
          <div className="mt-4 space-y-2">
            {[
              { key: "PENDING", label: "Menunggu", color: "bg-amber-100 text-amber-700" },
              { key: "PROCESSING", label: "Diproses", color: "bg-blue-100 text-blue-700" },
              { key: "SHIPPED", label: "Dikirim", color: "bg-indigo-100 text-indigo-700" },
              { key: "DELIVERED", label: "Selesai", color: "bg-emerald-100 text-emerald-700" },
              { key: "CANCELLED", label: "Dibatalkan", color: "bg-red-100 text-red-700" },
            ].map(({ key, label, color }) => (
              <div key={key} className="flex items-center justify-between rounded-xl bg-zinc-50 px-4 py-3">
                <p className="text-sm font-medium text-zinc-700">{label}</p>
                <span className={`rounded-full px-2.5 py-1 text-xs font-bold ${color}`}>
                  {statusMap[key] ?? 0}
                </span>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
