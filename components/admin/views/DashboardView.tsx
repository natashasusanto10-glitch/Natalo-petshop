import { DashboardRevenueChart } from "./DashboardRevenueChart";
import type { DashboardRevenue } from "@/lib/admin/dashboard-revenue";
import { AdminDisclosure } from "@/components/admin/ui/AdminDisclosure";
import Link from "next/link";
import { formatRupiah } from "@/lib/format";
import {
  StatCard,
  SectionCard,
  EmptyState,
  Badge,
  Button,
  AdminPage,
  STATUS_BADGE_VARIANT,
  type StatCardVariant,
} from "@/components/admin/ui";
const STATUS_LABELS: Record<string, string> = {
  PENDING: "Order Baru",
  PAID: "Sudah Dibayar",
  PROCESSING: "Diproses",
  READY_FOR_PICKUP: "Siap diambil",
  SHIPPED: "Dikirim",
  DELIVERED: "Selesai",
  CANCELLED: "Dibatalkan",
  REFUNDED: "Refund",
};

const PAY_LABELS: Record<string, string> = {
  UNPAID: "Belum bayar",
  PENDING: "Menunggu bayar",
  PAID: "Lunas",
  FAILED: "Gagal",
  EXPIRED: "Kedaluwarsa",
  REFUNDED: "Refund",
};

function formatDateTime(date: Date) {
  return new Intl.DateTimeFormat("id-ID", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Asia/Jakarta",
  }).format(date);
}

/** Inline SVG icon helper — 14×14, currentColor. */
function Icon({ d }: { d: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      className="h-3.5 w-3.5"
    >
      <path d={d} />
    </svg>
  );
}

const ICONS = {
  newOrder:
    "M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2M9 3h6v4H9z",
  wallet:
    "M21 12V7H5a2 2 0 0 1 0-4h14v4M3 5v14a2 2 0 0 0 2 2h16v-5M18 12a2 2 0 0 0 0 4h4v-4Z",
  check: "M20 6 9 17l-5-5",
  truck:
    "M3 5h11v12H3zM14 9h4l3 4v4h-7M7 16a2 2 0 1 0 0 4a2 2 0 1 0 0-4M18 16a2 2 0 1 0 0 4a2 2 0 1 0 0-4",
  sales: "M3 3v18h18M7 15l4-4 3 3 5-5",
  stock: "M3 7l9-4 9 4v10l-9 4-9-4V7Zm0 0 9 4 9-4M12 11v10M7 5l9 4",
  alert: "M12 9v4M12 17h.01M3 12 12 3l9 9-9 9-9-9Z",
  variant: "M3 7h18M3 12h18M3 17h12",
  voucher:
    "M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82zM7 7h.01",
  clock: "M12 6v6l4 2M3 12a9 9 0 1 0 18 0 9 9 0 0 0-18 0z",
};

export type DashboardViewProps = {
  greeting: string;
  adminName: string;
  now: Date;
  paidUnshippedCount: number;
  verificationCount: number;
  pickupCount: number;
  revenue: DashboardRevenue;
  stats: Array<{
    label: string;
    value: string | number;
    helper: string;
    href: string;
    variant: StatCardVariant;
    iconPath: string;
    trend?: { value: number; suffix?: string };
  }>;
  actionOrders: Array<{
    id: string;
    orderNumber: string;
    customerName: string;
    createdAt: Date;
    status: string;
    paymentStatus: string;
    total: number;
    items: Array<{ quantity: number }>;
  }>;
  lowStockProducts: Array<{
    id: string;
    name: string;
    stock: number;
    price: number;
  }>;
  outOfStockProducts: Array<{
    id: string;
    name: string;
    stock: number;
    price: number;
  }>;
  outOfStockVariants: Array<{
    id: string;
    sku: string | null;
    product: { id: string; name: string };
    options: Array<{ option: { value: string } }>;
  }>;
  expiringVouchers: Array<{
    id: string;
    code: string;
    expiresAt: Date | null;
    usedCount: number;
    maxUsage: number | null;
  }>;
};
export function DashboardView({
  greeting,
  adminName,
  now,
  paidUnshippedCount,
  verificationCount,
  pickupCount,
  revenue,
  stats,
  actionOrders,
  lowStockProducts,
  outOfStockProducts,
  outOfStockVariants,
  expiringVouchers,
}: DashboardViewProps) {
  const priorities = [
    {
      label: "Verifikasi pembayaran",
      description: "Cocokkan bukti dan jumlah pembayaran",
      count: verificationCount,
      action: "Periksa",
      href: "/admin/orders?proof=PENDING_REVIEW",
      icon: ICONS.wallet,
    },
    {
      label: "Pesanan siap dikemas",
      description: "Lunas dan menunggu pengiriman",
      count: paidUnshippedCount,
      action: "Proses",
      href: "/admin/orders?status=NEED_PACKING",
      icon: ICONS.stock,
    },
    {
      label: "Pickup menunggu validasi",
      description: "Pesanan siap diambil pelanggan",
      count: pickupCount,
      action: "Validasi",
      href: "/admin/orders?type=SELF_PICKUP&status=READY_FOR_PICKUP&pay=PAID",
      icon: ICONS.truck,
    },
  ];
  return (
    <AdminPage
      maxWidth="xl"
      className="admin-operational-page admin-dashboard dashboard-approved"
    >
      <header className="dashboard-heading">
        <div>
          <p className="dashboard-eyebrow">
            {new Intl.DateTimeFormat("id-ID", {
              timeZone: "Asia/Jakarta",
              weekday: "long",
              day: "numeric",
              month: "long",
              year: "numeric",
            }).format(now)}
          </p>
          <h1>Ringkasan</h1>
          <p>
            {greeting}, {adminName}. Berikut prioritas toko hari ini.
          </p>
        </div>
        <Button href="/" variant="secondary" size="sm">
          Lihat toko <span aria-hidden="true">→</span>
        </Button>
      </header>
      <section aria-label="Ringkasan hari ini" className="admin-stat-grid">
        {stats.slice(0, 4).map((stat) => (
          <StatCard
            key={stat.label}
            {...stat}
            icon={<Icon d={stat.iconPath} />}
          />
        ))}
      </section>
      <div className="dashboard-main-grid">
        <section className="admin-section dashboard-priorities">
          <header className="dashboard-panel-head">
            <div>
              <h2>Prioritas hari ini</h2>
              <p>Pekerjaan yang membutuhkan perhatian.</p>
            </div>
            <Badge variant="neutral">
              {new Intl.NumberFormat("id-ID").format(
                priorities.reduce((sum, priority) => sum + priority.count, 0)
              )}{" "}
              tugas
            </Badge>
          </header>
          <div className="dashboard-queue">
            {priorities.map((priority) => (
              <div className="dashboard-queue-row" key={priority.label}>
                <span className="dashboard-queue-icon" aria-hidden="true">
                  <Icon d={priority.icon} />
                </span>
                <div className="min-w-0">
                  <h3>{priority.label}</h3>
                  <p>{priority.description}</p>
                </div>
                <div className="dashboard-queue-action">
                  <strong>
                    {new Intl.NumberFormat("id-ID").format(priority.count)}
                  </strong>
                  <Link
                    href={priority.href}
                    aria-label={`${priority.action}: ${priority.label}`}
                  >
                    {priority.action}
                  </Link>
                </div>
              </div>
            ))}
          </div>
        </section>
        <DashboardRevenueChart revenue={revenue} />
      </div>
      <section
        className="admin-section dashboard-recent-orders"
        aria-labelledby="recent-orders-heading"
      >
        <header className="dashboard-panel-head">
          <div>
            <h2 id="recent-orders-heading">Pesanan terbaru</h2>
            <p>Pantau pembayaran dan proses pemenuhan.</p>
          </div>
          <Link href="/admin/orders" className="admin-section-action">
            Semua pesanan <span aria-hidden="true">→</span>
          </Link>
        </header>
        {actionOrders.length ? (
          <div className="dashboard-orders-table">
            <table>
              <thead>
                <tr>
                  <th scope="col">Pesanan</th>
                  <th scope="col">Pelanggan</th>
                  <th scope="col">Total / pembayaran</th>
                  <th scope="col">Status</th>
                </tr>
              </thead>
              <tbody>
                {actionOrders.slice(0, 4).map((order) => (
                  <tr key={order.id}>
                    <td>
                      <Link href={`/admin/orders/${order.id}`}>
                        {order.orderNumber}
                      </Link>
                      <small>{formatDateTime(order.createdAt)}</small>
                    </td>
                    <td>
                      {order.customerName}
                      <small>
                        {order.items.reduce(
                          (sum, item) => sum + item.quantity,
                          0
                        )}{" "}
                        item
                      </small>
                    </td>
                    <td>
                      <strong>{formatRupiah(order.total)}</strong>
                      <small>
                        {PAY_LABELS[order.paymentStatus] ?? order.paymentStatus}
                      </small>
                    </td>
                    <td>
                      <Badge
                        variant={
                          STATUS_BADGE_VARIANT[order.status] ?? "neutral"
                        }
                      >
                        {STATUS_LABELS[order.status] ?? order.status}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <EmptyState
            title="Belum ada pesanan"
            description="Pesanan terbaru akan tampil di sini."
          />
        )}
      </section>
      <div className="dashboard-extra">
        <AdminDisclosure title="Ringkasan operasional lainnya">
          <section
            className="admin-stat-grid admin-secondary-stats"
            aria-label="Metrik operasional tambahan"
          >
            {stats.slice(4).map((stat) => (
              <StatCard
                key={stat.label}
                {...stat}
                icon={<Icon d={stat.iconPath} />}
              />
            ))}
          </section>
          <div className="mt-5 grid gap-5 xl:grid-cols-2">
            <StockPanel
              title="Produk Stok Menipis"
              emoji="⚠️"
              emptyText="Tidak ada stok menipis."
              products={lowStockProducts}
            />
            <StockPanel
              title="Produk Habis"
              emoji="🚫"
              emptyText="Tidak ada produk habis."
              products={outOfStockProducts}
              danger
            />
            <VariantStockPanel variants={outOfStockVariants} />
            <ExpiringVoucherPanel vouchers={expiringVouchers} now={now} />
          </div>
          <div className="mt-5 flex flex-wrap gap-3">
            <Button href="/admin/abuse-flags" variant="secondary" size="sm">
              Indikasi penyalahgunaan
            </Button>
            <Button href="/admin/audit-log" variant="secondary" size="sm">
              Riwayat aktivitas
            </Button>
            <Button href="/admin/danger-zone" variant="dangerSoft" size="sm">
              Pengelolaan data lanjutan
            </Button>
          </div>
        </AdminDisclosure>
      </div>
    </AdminPage>
  );
}

function StockPanel({
  title,
  emoji,
  emptyText,
  products,
  danger = false,
}: {
  title: string;
  emoji: string;
  emptyText: string;
  products: Array<{ id: string; name: string; stock: number; price: number }>;
  danger?: boolean;
}) {
  return (
    <SectionCard
      title={title}
      action={{ label: "Kelola", href: "/admin/products" }}
      density="tight"
    >
      {products.length > 0 ? (
        <div className="space-y-2 p-3 md:p-4">
          {products.map((product) => (
            <Link
              key={product.id}
              href={`/admin/products/${product.id}/edit`}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center justify-between gap-3 rounded-xl bg-zinc-50 p-3 text-sm transition hover:bg-zinc-100"
            >
              <div className="min-w-0">
                <p className="truncate font-bold text-zinc-950">
                  {product.name}
                </p>
                <p className="mt-0.5 text-xs text-zinc-500">
                  {formatRupiah(product.price)}
                </p>
              </div>
              <Badge variant={danger ? "danger" : "warning"} size="md">
                Stok {product.stock}
              </Badge>
            </Link>
          ))}
        </div>
      ) : (
        <EmptyState icon={emoji} title={emptyText} />
      )}
    </SectionCard>
  );
}

function VariantStockPanel({
  variants,
}: {
  variants: Array<{
    id: string;
    sku: string | null;
    product: { id: string; name: string };
    options: Array<{ option: { value: string } }>;
  }>;
}) {
  return (
    <SectionCard
      title="Varian stok habis"
      action={{ label: "Kelola", href: "/admin/stock" }}
      density="tight"
    >
      {variants.length > 0 ? (
        <div className="space-y-2 p-3 md:p-4">
          {variants.map((variant) => {
            const optionLabel = variant.options
              .map((o) => o.option.value)
              .join(" / ");
            return (
              <Link
                key={variant.id}
                href={`/admin/products/${variant.product.id}/edit`}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center justify-between gap-3 rounded-xl bg-zinc-50 p-3 text-sm transition hover:bg-zinc-100"
              >
                <div className="min-w-0">
                  <p className="truncate font-bold text-zinc-950">
                    {variant.product.name}
                  </p>
                  <p className="mt-0.5 truncate text-xs text-zinc-500">
                    {optionLabel || variant.sku || "Varian"}
                  </p>
                </div>
                <Badge variant="danger" size="md">
                  Stok 0
                </Badge>
              </Link>
            );
          })}
        </div>
      ) : (
        <EmptyState icon="✅" title="Tidak ada varian yang habis." />
      )}
    </SectionCard>
  );
}

function ExpiringVoucherPanel({
  vouchers,
  now,
}: {
  vouchers: Array<{
    id: string;
    code: string;
    expiresAt: Date | null;
    usedCount: number;
    maxUsage: number | null;
  }>;
  now: Date;
}) {
  return (
    <SectionCard
      title="Voucher segera berakhir"
      action={{ label: "Kelola", href: "/admin/vouchers" }}
      density="tight"
    >
      {vouchers.length > 0 ? (
        <div className="space-y-2 p-3 md:p-4">
          {vouchers.map((voucher) => {
            const daysLeft = voucher.expiresAt
              ? Math.max(
                  0,
                  Math.ceil(
                    (voucher.expiresAt.getTime() - now.getTime()) /
                      (24 * 60 * 60 * 1000)
                  )
                )
              : null;
            const usageLabel =
              voucher.maxUsage != null
                ? `${voucher.usedCount}/${voucher.maxUsage} dipakai`
                : `${voucher.usedCount} dipakai`;
            return (
              <div
                key={voucher.id}
                className="flex items-center justify-between gap-3 rounded-xl bg-zinc-50 p-3 text-sm"
              >
                <div className="min-w-0">
                  <p className="truncate font-bold text-zinc-950">
                    {voucher.code}
                  </p>
                  <p className="mt-0.5 truncate text-xs text-zinc-500">
                    {usageLabel}
                  </p>
                </div>
                <Badge variant="warning" size="md">
                  {daysLeft != null ? `${daysLeft} hari` : "—"}
                </Badge>
              </div>
            );
          })}
        </div>
      ) : (
        <EmptyState icon="🎟️" title="Tidak ada voucher yang segera berakhir." />
      )}
    </SectionCard>
  );
}
