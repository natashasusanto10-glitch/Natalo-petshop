import { formatRupiah } from "@/lib/format";
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
export type ReportsViewProps = {
  monthName: string;
  thisMonthRevenue: number;
  lastMonthRevenue: number;
  revenueGrowth: number | null;
  ordersThisMonth: number;
  ordersLastMonth: number;
  topProducts: Array<{ id: string; name: string; quantity: number }>;
  statusMap: Record<string, number>;
};
export function ReportsView({
  monthName,
  thisMonthRevenue,
  lastMonthRevenue,
  revenueGrowth,
  ordersThisMonth,
  ordersLastMonth,
  topProducts,
  statusMap,
}: ReportsViewProps) {
  const STATUS_ROWS: Array<{
    key: string;
    label: string;
    variant: BadgeVariant;
  }> = [
    { key: "PENDING", label: "Menunggu", variant: "warning" },
    { key: "PAID", label: "Sudah dibayar", variant: "success" },
    { key: "READY_FOR_PICKUP", label: "Siap diambil", variant: "success" },
    { key: "REFUNDED", label: "Refund", variant: "purple" },
    { key: "PROCESSING", label: "Diproses", variant: "info" },
    { key: "SHIPPED", label: "Dikirim", variant: "info" },
    { key: "DELIVERED", label: "Selesai", variant: "success" },
    { key: "CANCELLED", label: "Dibatalkan", variant: "danger" },
  ];

  return (
    <AdminPage
      maxWidth="xl"
      className="admin-operational-page admin-refined-page"
    >
      <PageHeader
        eyebrow="Performa toko"
        title="Laporan"
        subtitle={`Ringkasan performa toko — ${monthName}.`}
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            Kembali ke ringkasan
          </Button>
        }
      />

      {/* This month stats */}
      <section className="admin-stat-grid">
        <StatCard
          label="Pendapatan Bulan Ini"
          value={formatRupiah(thisMonthRevenue)}
          helper={
            revenueGrowth !== null
              ? `vs ${formatRupiah(lastMonthRevenue)}`
              : "—"
          }
          variant="accent"
          trend={revenueGrowth !== null ? { value: revenueGrowth } : undefined}
        />
        <StatCard
          label="Pendapatan Bulan Lalu"
          value={formatRupiah(lastMonthRevenue)}
          helper="Pesanan lunas · termasuk ongkir"
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

      <p className="mt-3 text-xs text-slate-500">
        Pendapatan dari pesanan lunas, termasuk ongkir, berdasarkan tanggal
        pesanan (WIB). Pesanan dibatalkan dan refund tidak dihitung.
      </p>

      <div className="mt-6 grid gap-5 lg:grid-cols-2">
        <SectionCard
          title="Produk Terlaris"
          subtitle="10 produk · unit terjual dari pesanan lunas · semua periode · seluruh varian"
        >
          {topProducts.length > 0 ? (
            <div className="space-y-2">
              {topProducts.map((item, i) => (
                <div
                  key={item.id}
                  className="flex items-center gap-3 rounded-xl bg-zinc-50 px-4 py-3 transition hover:bg-zinc-100"
                >
                  <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-natalo-50 text-xs font-semibold text-natalo-700">
                    {i + 1}
                  </span>
                  <p className="min-w-0 flex-1 text-sm font-bold text-zinc-900">
                    {item.name}
                  </p>
                  <Badge variant="info" size="md">
                    {item.quantity}×
                  </Badge>
                </div>
              ))}
            </div>
          ) : (
            <EmptyState
              icon="📈"
              title="Belum ada data"
              description="Akan muncul setelah ada pesanan lunas yang tidak dibatalkan atau di-refund."
            />
          )}
        </SectionCard>

        <SectionCard
          title="Distribusi Status Order"
          subtitle="Seluruh pesanan · semua periode"
        >
          <div className="space-y-4">
            {STATUS_ROWS.map(({ key, label, variant }) => (
              <div key={key} className="admin-report-status">
                <div className="flex items-center justify-between gap-3">
                  <p className="text-sm font-medium text-slate-700">{label}</p>
                  <Badge variant={variant} size="md">
                    {statusMap[key] ?? 0}
                  </Badge>
                </div>
                <div className="admin-report-track" aria-hidden="true">
                  <span
                    style={{
                      width: `${Math.max(
                        0,
                        ((statusMap[key] ?? 0) /
                          Math.max(1, ...Object.values(statusMap))) *
                          100
                      )}%`,
                    }}
                  />
                </div>
              </div>
            ))}
          </div>
        </SectionCard>
      </div>
    </AdminPage>
  );
}
