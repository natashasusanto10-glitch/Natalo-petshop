import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { requireAdminSession } from "@/lib/session-guards";
import {
  PageHeader,
  StatCard,
  SectionCard,
  EmptyState,
  Badge,
  Button,
  AdminPage,
  type BadgeVariant,
} from "@/components/admin/ui";

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
    59,
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
          ((thisMonthRevenue - lastMonthRevenue) / lastMonthRevenue) * 100,
        )
      : null;

  const statusMap: Record<string, number> = {};
  for (const s of ordersByStatus) statusMap[s.status] = s._count;

  const monthName = now.toLocaleDateString("id-ID", {
    month: "long",
    year: "numeric",
  });

  const STATUS_ROWS: Array<{
    key: string;
    label: string;
    variant: BadgeVariant;
  }> = [
    { key: "PENDING", label: "Menunggu", variant: "warning" },
    { key: "PROCESSING", label: "Diproses", variant: "info" },
    { key: "SHIPPED", label: "Dikirim", variant: "info" },
    { key: "DELIVERED", label: "Selesai", variant: "success" },
    { key: "CANCELLED", label: "Dibatalkan", variant: "danger" },
  ];

  return (
    <AdminPage maxWidth="lg">
      <PageHeader
        title="📊 Laporan"
        subtitle={`Ringkasan performa toko — ${monthName}.`}
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            ← Dashboard
          </Button>
        }
      />

      {/* This month stats */}
      <section className="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatCard
          label="Pendapatan Bulan Ini"
          value={formatRupiah(thisMonthRevenue)}
          helper={
            revenueGrowth !== null ? `vs ${formatRupiah(lastMonthRevenue)}` : "—"
          }
          variant="accent"
          trend={revenueGrowth !== null ? { value: revenueGrowth } : undefined}
        />
        <StatCard
          label="Pendapatan Bulan Lalu"
          value={formatRupiah(lastMonthRevenue)}
          helper="Periode sebelumnya"
          variant="default"
        />
        <StatCard
          label="Order Bulan Ini"
          value={ordersThisMonth}
          helper="Termasuk semua status"
          variant="primary"
        />
        <StatCard
          label="Order Bulan Lalu"
          value={ordersLastMonth}
          helper="Periode sebelumnya"
          variant="default"
        />
      </section>

      <div className="mt-6 grid gap-5 lg:grid-cols-2">
        <SectionCard title="Produk Terlaris" subtitle="Top 10 by quantity sold">
          {topProducts.length > 0 ? (
            <div className="space-y-2">
              {topProducts.map((item, i) => (
                <div
                  key={item.name}
                  className="flex items-center gap-3 rounded-xl bg-zinc-50 px-4 py-3 transition hover:bg-zinc-100"
                >
                  <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-natalo-50 text-xs font-black text-natalo-700">
                    {i + 1}
                  </span>
                  <p className="flex-1 truncate text-sm font-bold text-zinc-900">
                    {item.name}
                  </p>
                  <Badge variant="info" size="md">
                    {item._sum.quantity ?? 0}×
                  </Badge>
                </div>
              ))}
            </div>
          ) : (
            <EmptyState
              icon="📈"
              title="Belum ada data"
              description="Akan muncul setelah ada order pertama."
            />
          )}
        </SectionCard>

        <SectionCard
          title="Distribusi Status Order"
          subtitle="Total per status semua-waktu"
        >
          <div className="space-y-2">
            {STATUS_ROWS.map(({ key, label, variant }) => (
              <div
                key={key}
                className="flex items-center justify-between rounded-xl bg-zinc-50 px-4 py-3"
              >
                <p className="text-sm font-bold text-zinc-800">{label}</p>
                <Badge variant={variant} size="md">
                  {statusMap[key] ?? 0}
                </Badge>
              </div>
            ))}
          </div>
        </SectionCard>
      </div>
    </AdminPage>
  );
}
