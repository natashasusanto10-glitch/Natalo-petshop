import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatRupiah, jakartaTodayRange } from "@/lib/format";
import { getSession } from "@/lib/auth";
import {
  StatCard,
  SectionCard,
  EmptyState,
  PageHeader,
  Badge,
  STATUS_BADGE_VARIANT,
  PAY_BADGE_VARIANT,
} from "@/components/admin/ui";

const STATUS_LABELS: Record<string, string> = {
  PENDING: "Order Baru",
  PAID: "Sudah Dibayar",
  PROCESSING: "Diproses",
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

const LOW_STOCK_LIMIT = 5;

function formatDateTime(date: Date) {
  return new Intl.DateTimeFormat("id-ID", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Asia/Jakarta",
  }).format(date);
}

/** Simple greeting based on Jakarta hour. */
function getGreeting() {
  const hour = new Date().toLocaleString("en-US", {
    timeZone: "Asia/Jakarta",
    hour: "2-digit",
    hour12: false,
  });
  const h = parseInt(hour, 10);
  if (h < 11) return "Selamat pagi";
  if (h < 15) return "Selamat siang";
  if (h < 19) return "Selamat sore";
  return "Selamat malam";
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
  newOrder: "M9 5H7a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2M9 3h6v4H9z",
  wallet: "M21 12V7H5a2 2 0 0 1 0-4h14v4M3 5v14a2 2 0 0 0 2 2h16v-5M18 12a2 2 0 0 0 0 4h4v-4Z",
  check: "M20 6 9 17l-5-5",
  truck: "M16 3h-2v9.5l-1.5-1.5L11 12.5l3 3 3-3-1.5-1.5L14 12.5V3h2M3 7v10a2 2 0 0 0 2 2h11M3 7l5-4h4",
  sales: "M3 3v18h18M7 15l4-4 3 3 5-5",
  stock: "M20 7H4a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1V8a1 1 0 0 0-1-1ZM16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2",
  alert: "M12 9v4M12 17h.01M3 12 12 3l9 9-9 9-9-9Z",
  variant: "M3 7h18M3 12h18M3 17h12",
  voucher: "M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82zM7 7h.01",
  clock: "M12 6v6l4 2M3 12a9 9 0 1 0 18 0 9 9 0 0 0-18 0z",
};

export default async function AdminDashboardPage() {
  const session = await getSession("ADMIN");
  const { start: todayStart, end: todayEnd } = jakartaTodayRange();

  const now = new Date();
  const expiringSoonCutoff = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
  const usableVoucherWhere = {
    isActive: true,
    startsAt: { lte: now },
    OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
    AND: [
      {
        OR: [
          { maxUsage: null },
          { usedCount: { lt: prisma.voucher.fields.maxUsage } },
        ],
      },
    ],
  };

  const [
    orderStatusCounts,
    waitingPaymentCount,
    todaySales,
    paidUnshippedCount,
    actionOrders,
    lowStockCount,
    outOfStockCount,
    lowStockProducts,
    outOfStockProducts,
    outOfStockVariantCount,
    outOfStockVariants,
    voucherActiveCount,
    voucherExpiringCount,
    expiringVouchers,
  ] = await Promise.all([
    prisma.order.groupBy({ by: ["status"], _count: true }),
    prisma.order.count({
      where: { paymentStatus: { in: ["UNPAID", "PENDING"] }, status: { notIn: ["CANCELLED", "REFUNDED"] } },
    }),
    prisma.order.aggregate({
      where: {
        createdAt: { gte: todayStart, lte: todayEnd },
        paymentStatus: "PAID",
        status: { notIn: ["CANCELLED", "REFUNDED"] },
      },
      _sum: { total: true },
    }),
    prisma.order.count({
      where: {
        paymentStatus: "PAID",
        status: { in: ["PENDING", "PAID", "PROCESSING"] },
      },
    }),
    prisma.order.findMany({
      where: {
        OR: [
          { status: "PENDING" },
          { status: "PAID" },
          { status: "PROCESSING" },
          { status: "SHIPPED" },
          { paymentStatus: { in: ["UNPAID", "PENDING"] }, status: { notIn: ["CANCELLED", "DELIVERED", "REFUNDED"] } },
        ],
      },
      orderBy: { createdAt: "desc" },
      take: 8,
      include: { items: { select: { quantity: true } } },
    }),
    prisma.product.count({ where: { isActive: true, stock: { gt: 0, lte: LOW_STOCK_LIMIT } } }),
    prisma.product.count({ where: { isActive: true, stock: 0 } }),
    prisma.product.findMany({
      where: { isActive: true, stock: { gt: 0, lte: LOW_STOCK_LIMIT } },
      orderBy: { stock: "asc" },
      take: 8,
      select: { id: true, name: true, stock: true, price: true },
    }),
    prisma.product.findMany({
      where: { isActive: true, stock: 0 },
      orderBy: { updatedAt: "desc" },
      take: 8,
      select: { id: true, name: true, stock: true, price: true },
    }),
    prisma.productVariant.count({
      where: {
        isActive: true,
        deletedAt: null,
        stock: 0,
        product: { isActive: true },
      },
    }),
    prisma.productVariant.findMany({
      where: {
        isActive: true,
        deletedAt: null,
        stock: 0,
        product: { isActive: true },
      },
      orderBy: { updatedAt: "desc" },
      take: 8,
      select: {
        id: true,
        sku: true,
        product: { select: { id: true, name: true } },
        options: { select: { option: { select: { value: true } } } },
      },
    }),
    prisma.voucher.count({
      where: usableVoucherWhere,
    }),
    prisma.voucher.count({
      where: {
        ...usableVoucherWhere,
        expiresAt: { gt: now, lte: expiringSoonCutoff },
      },
    }),
    prisma.voucher.findMany({
      where: {
        ...usableVoucherWhere,
        expiresAt: { gt: now, lte: expiringSoonCutoff },
      },
      orderBy: { expiresAt: "asc" },
      take: 5,
      select: { id: true, code: true, expiresAt: true, usedCount: true, maxUsage: true },
    }),
  ]);

  const countMap: Record<string, number> = {};
  for (const row of orderStatusCounts) countMap[row.status] = row._count;

  // Stat tiles — variant assigned by semantic urgency:
  //   warning = perlu action admin
  //   danger  = stok / abuse — urgent
  //   success = state oke / sales positif
  //   primary = info netral important
  //   accent  = highlight (sales hari ini — feature angka utama)
  const stats: Array<{
    label: string;
    value: string | number;
    helper: string;
    href: string;
    variant: "default" | "primary" | "success" | "warning" | "danger" | "accent";
    iconPath: string;
  }> = [
    {
      label: "Total Penjualan Hari Ini",
      value: formatRupiah(todaySales._sum.total ?? 0),
      helper: "Order lunas hari ini",
      href: "/admin/orders?pay=PAID",
      variant: "accent",
      iconPath: ICONS.sales,
    },
    {
      label: "Order Baru",
      value: countMap.PENDING ?? 0,
      helper: "Belum diproses",
      href: "/admin/orders?status=PENDING",
      variant: "warning",
      iconPath: ICONS.newOrder,
    },
    {
      label: "Menunggu Pembayaran",
      value: waitingPaymentCount,
      helper: "Belum lunas / verifikasi",
      href: "/admin/orders?pay=WAITING",
      variant: "warning",
      iconPath: ICONS.wallet,
    },
    {
      label: "Sudah Dibayar",
      value: countMap.PAID ?? 0,
      helper: "Siap mulai packing",
      href: "/admin/orders?status=PAID",
      variant: "success",
      iconPath: ICONS.check,
    },
    {
      label: "Diproses",
      value: countMap.PROCESSING ?? 0,
      helper: "Perlu packing",
      href: "/admin/orders?status=PROCESSING",
      variant: "primary",
      iconPath: ICONS.newOrder,
    },
    {
      label: "Dikirim",
      value: countMap.SHIPPED ?? 0,
      helper: "Dalam pengiriman",
      href: "/admin/orders?status=SHIPPED",
      variant: "primary",
      iconPath: ICONS.truck,
    },
    {
      label: "Selesai",
      value: countMap.DELIVERED ?? 0,
      helper: "Order selesai",
      href: "/admin/orders?status=DELIVERED",
      variant: "success",
      iconPath: ICONS.check,
    },
    {
      label: "Produk Stok Menipis",
      value: lowStockCount,
      helper: `Stok 1-${LOW_STOCK_LIMIT}`,
      href: "/admin/products",
      variant: "warning",
      iconPath: ICONS.stock,
    },
    {
      label: "Produk Habis",
      value: outOfStockCount,
      helper: "Stok 0",
      href: "/admin/products",
      variant: "danger",
      iconPath: ICONS.alert,
    },
    {
      label: "Varian Habis",
      value: outOfStockVariantCount,
      helper: "Varian aktif stok 0",
      href: "/admin/stock",
      variant: "danger",
      iconPath: ICONS.variant,
    },
    {
      label: "Voucher Aktif",
      value: voucherActiveCount,
      helper: "Berlaku saat ini",
      href: "/admin/vouchers",
      variant: "primary",
      iconPath: ICONS.voucher,
    },
    {
      label: "Voucher Expiring",
      value: voucherExpiringCount,
      helper: "Habis dalam 7 hari",
      href: "/admin/vouchers",
      variant: "warning",
      iconPath: ICONS.clock,
    },
  ];

  return (
    <div className="mx-auto max-w-7xl px-4 py-5 md:py-8">
      <PageHeader
        title="Dashboard Admin"
        subtitle={`${getGreeting()}, ${session?.name ?? "Admin"}. Fokus: order masuk & stok kritis.`}
        actions={
          <>
            <Link
              href="/admin/abuse-flags"
              className="inline-flex items-center gap-1.5 rounded-full border border-red-200 bg-red-50 px-3.5 py-2 text-xs font-bold text-red-700 transition hover:border-red-400 hover:bg-red-100"
            >
              🚨 Abuse Flags
            </Link>
            <Link
              href="/admin/audit-log"
              className="inline-flex items-center gap-1.5 rounded-full border border-zinc-200 bg-white px-3.5 py-2 text-xs font-bold text-zinc-700 transition hover:border-zinc-400 hover:bg-zinc-50"
            >
              📋 Audit Log
            </Link>
          </>
        }
      />

      {/* Hero CTA — gradient orange/amber untuk warm "action perlu" feel.
          Beda dari card lain supaya kelihatan jelas dari kejauhan saat
          admin first-open dashboard. */}
      {paidUnshippedCount > 0 && (
        <Link
          href="/admin/orders?status=NEED_PACKING"
          className="group mt-6 flex items-center gap-4 overflow-hidden rounded-2xl border border-emerald-200 bg-gradient-to-r from-emerald-50 via-emerald-50 to-white p-4 transition hover:-translate-y-0.5 hover:border-emerald-400 hover:shadow-[0_10px_30px_-12px_rgba(16,185,129,0.4)] md:p-5"
        >
          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-emerald-500 text-2xl text-white shadow-sm md:h-14 md:w-14">
            📦
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-black text-emerald-900 md:text-base">
              {paidUnshippedCount} order lunas siap dipacking
            </p>
            <p className="mt-0.5 text-xs font-medium text-emerald-700 md:text-sm">
              Pembayaran sudah masuk. Klik untuk buka daftar dan mulai packing.
            </p>
          </div>
          <span className="hidden shrink-0 items-center gap-1.5 rounded-full bg-emerald-500 px-4 py-2 text-xs font-bold text-white shadow-sm group-hover:bg-emerald-600 md:inline-flex">
            Lihat daftar →
          </span>
        </Link>
      )}

      {/* Stats grid — 2 col mobile, 4 col desktop. Tile pertama (sales)
          highlighted dengan accent orange, lainnya semantic per status. */}
      <section className="mt-6 grid grid-cols-2 gap-2.5 sm:gap-3 lg:grid-cols-4">
        {stats.map((stat) => (
          <StatCard
            key={stat.label}
            label={stat.label}
            value={stat.value}
            helper={stat.helper}
            href={stat.href}
            variant={stat.variant}
            icon={<Icon d={stat.iconPath} />}
          />
        ))}
      </section>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_360px]">
        <SectionCard
          title="Order Perlu Diproses"
          subtitle="Prioritas: pembayaran menunggu, order baru, packing, dan pengiriman."
          action={{ label: "Semua order", href: "/admin/orders" }}
          density="tight"
        >
          {actionOrders.length > 0 ? (
            <div className="divide-y divide-zinc-100">
              {actionOrders.map((order) => {
                const itemCount = order.items.reduce(
                  (sum, item) => sum + item.quantity,
                  0,
                );
                const initial = order.customerName?.[0]?.toUpperCase() ?? "?";
                return (
                  <Link
                    key={order.id}
                    href={`/admin/orders/${order.id}`}
                    className="grid items-center gap-3 px-4 py-3.5 text-sm transition hover:bg-zinc-50 md:grid-cols-[1.4fr_1fr_auto] md:px-5"
                  >
                    <div className="flex min-w-0 items-center gap-3">
                      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-natalo-50 text-sm font-black text-natalo-700">
                        {initial}
                      </div>
                      <div className="min-w-0">
                        <p className="truncate font-black text-zinc-950">
                          {order.orderNumber}
                        </p>
                        <p className="mt-0.5 truncate text-xs text-zinc-600">
                          {order.customerName} · {formatDateTime(order.createdAt)}
                        </p>
                      </div>
                    </div>
                    <div className="flex flex-wrap items-center gap-1.5">
                      <Badge
                        variant={
                          STATUS_BADGE_VARIANT[order.status] ?? "neutral"
                        }
                      >
                        {STATUS_LABELS[order.status] ?? order.status}
                      </Badge>
                      <Badge
                        variant={
                          PAY_BADGE_VARIANT[order.paymentStatus] ?? "neutral"
                        }
                      >
                        {PAY_LABELS[order.paymentStatus] ?? order.paymentStatus}
                      </Badge>
                      <Badge variant="neutral">{itemCount} item</Badge>
                    </div>
                    <div className="text-right">
                      <p className="font-black text-zinc-950">
                        {formatRupiah(order.total)}
                      </p>
                      <p className="mt-0.5 text-[11px] font-bold text-natalo-600">
                        Buka detail →
                      </p>
                    </div>
                  </Link>
                );
              })}
            </div>
          ) : (
            <EmptyState
              icon="🎉"
              title="Semua order sudah ditangani"
              description="Tidak ada order yang perlu di-process sekarang. Take a breather!"
            />
          )}
        </SectionCard>

        <aside className="space-y-5">
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
        </aside>
      </div>

      {/* Danger zone link — subtle styling supaya tidak accidentally
          tapped tapi findable kalau admin perlu wipe data sebelum launch. */}
      <div className="mt-12 border-t border-zinc-100 pt-6 text-center">
        <Link
          href="/admin/danger-zone"
          className="inline-flex items-center gap-2 rounded-full border border-red-200 bg-white px-4 py-2 text-xs font-bold text-red-700 transition hover:bg-red-50"
        >
          ⚠️ Danger Zone — Reset Database
        </Link>
      </div>
    </div>
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
              className="flex items-center justify-between gap-3 rounded-xl bg-zinc-50 p-3 text-sm transition hover:bg-zinc-100"
            >
              <div className="min-w-0">
                <p className="truncate font-bold text-zinc-950">{product.name}</p>
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
      title="Varian Habis"
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
      title="Voucher Expiring"
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
                      (24 * 60 * 60 * 1000),
                  ),
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
        <EmptyState icon="🎟️" title="Tidak ada voucher expiring." />
      )}
    </SectionCard>
  );
}
