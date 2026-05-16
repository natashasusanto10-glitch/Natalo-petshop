import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatRupiah, jakartaTodayRange } from "@/lib/format";
import { getSession } from "@/lib/auth";
import { AdminInstallPrompt } from "@/components/AdminInstallPrompt";

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

  const stats = [
    {
      label: "Order Baru",
      value: countMap.PENDING ?? 0,
      helper: "Belum diproses",
      href: "/admin/orders?status=PENDING",
    },
    {
      label: "Menunggu Pembayaran",
      value: waitingPaymentCount,
      helper: "Belum lunas / verifikasi",
      href: "/admin/orders?pay=WAITING",
    },
    {
      label: "Sudah Dibayar",
      value: countMap.PAID ?? 0,
      helper: "Siap mulai packing",
      href: "/admin/orders?status=PAID",
    },
    {
      label: "Diproses",
      value: countMap.PROCESSING ?? 0,
      helper: "Perlu packing",
      href: "/admin/orders?status=PROCESSING",
    },
    {
      label: "Dikirim",
      value: countMap.SHIPPED ?? 0,
      helper: "Dalam pengiriman",
      href: "/admin/orders?status=SHIPPED",
    },
    {
      label: "Selesai",
      value: countMap.DELIVERED ?? 0,
      helper: "Order selesai",
      href: "/admin/orders?status=DELIVERED",
    },
    {
      label: "Total Penjualan Hari Ini",
      value: formatRupiah(todaySales._sum.total ?? 0),
      helper: "Order lunas hari ini",
      href: "/admin/orders?pay=PAID",
    },
    {
      label: "Produk Stok Menipis",
      value: lowStockCount,
      helper: `Stok 1-${LOW_STOCK_LIMIT}`,
      href: "/admin/products",
    },
    {
      label: "Produk Habis",
      value: outOfStockCount,
      helper: "Stok 0",
      href: "/admin/products",
    },
    {
      label: "Varian Habis",
      value: outOfStockVariantCount,
      helper: "Varian aktif stok 0",
      href: "/admin/stock",
    },
    {
      label: "Voucher Aktif",
      value: voucherActiveCount,
      helper: "Berlaku saat ini",
      href: "/admin/vouchers",
    },
    {
      label: "Voucher Expiring",
      value: voucherExpiringCount,
      helper: "Habis dalam 7 hari",
      href: "/admin/vouchers",
    },
  ];

  return (
    <div className="mx-auto max-w-7xl px-4 py-5 md:py-8">
      <div>
        <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
          Dashboard Admin
        </h1>
        <p className="mt-1.5 text-sm text-zinc-600 md:mt-2">
          Masuk sebagai {session?.name ?? "Admin"}. Fokus utama: order masuk dan stok kritis.
        </p>
      </div>

      {paidUnshippedCount > 0 && (
        <Link
          href="/admin/orders?status=NEED_PACKING"
          className="mt-6 flex items-start gap-3 rounded-lg border border-emerald-200 bg-emerald-50 p-4 transition hover:border-emerald-400"
        >
          <span className="mt-0.5 text-xl">📦</span>
          <div className="flex-1">
            <p className="text-sm font-black text-emerald-900">
              {paidUnshippedCount} order lunas siap dipacking
            </p>
            <p className="mt-0.5 text-xs font-medium text-emerald-700">
              Pembayaran sudah masuk tetapi belum dikirim. Klik untuk buka daftar.
            </p>
          </div>
          <span className="text-xs font-bold text-emerald-700">Lihat &rarr;</span>
        </Link>
      )}

      <section className="mt-6 grid grid-cols-2 gap-2.5 sm:gap-3 lg:grid-cols-4">
        {stats.map((stat) => (
          <Link
            key={stat.label}
            href={stat.href}
            className="rounded-lg border border-zinc-200 bg-white p-3 transition hover:border-zinc-400 md:p-4"
          >
            <p className="text-[10px] font-bold uppercase tracking-wide text-zinc-500 md:text-xs">{stat.label}</p>
            <p className="mt-2 text-2xl font-black text-zinc-950 md:mt-3 md:text-3xl">{stat.value}</p>
            <p className="mt-0.5 text-[11px] font-medium text-zinc-500 md:mt-1 md:text-xs">{stat.helper}</p>
          </Link>
        ))}
      </section>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_360px]">
        <section className="rounded-lg border border-zinc-200 bg-white p-4 md:p-5">
          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0">
              <h2 className="text-base font-black text-zinc-950 md:text-lg">Order Perlu Diproses</h2>
              <p className="mt-1 hidden text-sm text-zinc-500 sm:block">
                Prioritas: pembayaran menunggu, order baru, packing, dan pengiriman.
              </p>
            </div>
            <Link href="/admin/orders" className="shrink-0 text-xs font-bold text-zinc-600 hover:text-zinc-950 md:text-sm">
              Semua order
            </Link>
          </div>

          <div className="mt-5 overflow-hidden rounded-lg border border-zinc-200">
            {actionOrders.length > 0 ? (
              <div className="divide-y divide-zinc-200">
                {actionOrders.map((order) => {
                  const itemCount = order.items.reduce((sum, item) => sum + item.quantity, 0);
                  return (
                    <Link
                      key={order.id}
                      href={`/admin/orders/${order.id}`}
                      className="grid gap-3 p-4 text-sm transition hover:bg-zinc-50 md:grid-cols-[1.2fr_1fr_auto]"
                    >
                      <div>
                        <p className="font-black text-zinc-950">{order.orderNumber}</p>
                        <p className="mt-1 text-zinc-600">{order.customerName}</p>
                        <p className="mt-1 text-xs text-zinc-500">{formatDateTime(order.createdAt)}</p>
                      </div>
                      <div className="flex flex-wrap items-start gap-2">
                        <StatusBadge>{STATUS_LABELS[order.status] ?? order.status}</StatusBadge>
                        <PaymentBadge>{PAY_LABELS[order.paymentStatus] ?? order.paymentStatus}</PaymentBadge>
                        <span className="rounded-full bg-zinc-100 px-3 py-1 text-xs font-bold text-zinc-600">
                          {itemCount} item
                        </span>
                      </div>
                      <div className="text-left md:text-right">
                        <p className="font-black text-zinc-950">{formatRupiah(order.total)}</p>
                        <p className="mt-1 text-xs font-bold text-zinc-500">Buka detail</p>
                      </div>
                    </Link>
                  );
                })}
              </div>
            ) : (
              <p className="p-5 text-sm text-zinc-500">Tidak ada order yang perlu diproses sekarang.</p>
            )}
          </div>
        </section>

        <aside className="space-y-6">
          <AdminInstallPrompt />

          <StockPanel
            title="Produk Stok Menipis"
            emptyText="Tidak ada stok menipis."
            products={lowStockProducts}
          />

          <StockPanel
            title="Produk Habis"
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
          className="inline-flex items-center gap-2 rounded-lg border border-red-200 bg-white px-4 py-2 text-xs font-bold text-red-700 transition hover:bg-red-50"
        >
          ⚠️ Danger Zone — Reset Database
        </Link>
      </div>
    </div>
  );
}

function StatusBadge({ children }: { children: React.ReactNode }) {
  return (
    <span className="rounded-full bg-blue-50 px-3 py-1 text-xs font-bold text-blue-700">
      {children}
    </span>
  );
}

function PaymentBadge({ children }: { children: React.ReactNode }) {
  return (
    <span className="rounded-full bg-amber-50 px-3 py-1 text-xs font-bold text-amber-700">
      {children}
    </span>
  );
}

function StockPanel({
  title,
  emptyText,
  products,
  danger = false,
}: {
  title: string;
  emptyText: string;
  products: Array<{ id: string; name: string; stock: number; price: number }>;
  danger?: boolean;
}) {
  return (
    <section className="rounded-lg border border-zinc-200 bg-white p-5">
      <div className="flex items-center justify-between gap-3">
        <h2 className="font-black text-zinc-950">{title}</h2>
        <Link href="/admin/products" className="text-xs font-bold text-zinc-500 hover:text-zinc-950">
          Kelola
        </Link>
      </div>

      <div className="mt-4 space-y-3">
        {products.length > 0 ? (
          products.map((product) => (
            <Link
              key={product.id}
              href={`/admin/products/${product.id}/edit`}
              className="flex justify-between gap-4 rounded-lg bg-zinc-50 p-3 text-sm transition hover:bg-zinc-100"
            >
              <div>
                <p className="font-bold text-zinc-950">{product.name}</p>
                <p className="mt-1 text-xs text-zinc-500">{formatRupiah(product.price)}</p>
              </div>
              <span
                className={`h-fit rounded-full px-3 py-1 text-xs font-black ${
                  danger ? "bg-red-100 text-red-700" : "bg-amber-100 text-amber-700"
                }`}
              >
                Stok {product.stock}
              </span>
            </Link>
          ))
        ) : (
          <p className="rounded-lg bg-zinc-50 p-4 text-sm text-zinc-500">{emptyText}</p>
        )}
      </div>
    </section>
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
    <section className="rounded-lg border border-zinc-200 bg-white p-5">
      <div className="flex items-center justify-between gap-3">
        <h2 className="font-black text-zinc-950">Varian Habis</h2>
        <Link href="/admin/stock" className="text-xs font-bold text-zinc-500 hover:text-zinc-950">
          Kelola
        </Link>
      </div>

      <div className="mt-4 space-y-3">
        {variants.length > 0 ? (
          variants.map((variant) => {
            const optionLabel = variant.options.map((o) => o.option.value).join(" / ");
            return (
              <Link
                key={variant.id}
                href={`/admin/products/${variant.product.id}/edit`}
                className="flex justify-between gap-4 rounded-lg bg-zinc-50 p-3 text-sm transition hover:bg-zinc-100"
              >
                <div className="min-w-0">
                  <p className="truncate font-bold text-zinc-950">{variant.product.name}</p>
                  <p className="mt-1 truncate text-xs text-zinc-500">
                    {optionLabel || variant.sku || "Varian"}
                  </p>
                </div>
                <span className="h-fit rounded-full bg-red-100 px-3 py-1 text-xs font-black text-red-700">
                  Stok 0
                </span>
              </Link>
            );
          })
        ) : (
          <p className="rounded-lg bg-zinc-50 p-4 text-sm text-zinc-500">
            Tidak ada varian yang habis.
          </p>
        )}
      </div>
    </section>
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
    <section className="rounded-lg border border-zinc-200 bg-white p-5">
      <div className="flex items-center justify-between gap-3">
        <h2 className="font-black text-zinc-950">Voucher Expiring</h2>
        <Link href="/admin/vouchers" className="text-xs font-bold text-zinc-500 hover:text-zinc-950">
          Kelola
        </Link>
      </div>

      <div className="mt-4 space-y-3">
        {vouchers.length > 0 ? (
          vouchers.map((voucher) => {
            const daysLeft = voucher.expiresAt
              ? Math.max(
                  0,
                  Math.ceil((voucher.expiresAt.getTime() - now.getTime()) / (24 * 60 * 60 * 1000)),
                )
              : null;
            const usageLabel =
              voucher.maxUsage != null
                ? `${voucher.usedCount}/${voucher.maxUsage} dipakai`
                : `${voucher.usedCount} dipakai`;
            return (
              <div
                key={voucher.id}
                className="flex justify-between gap-4 rounded-lg bg-zinc-50 p-3 text-sm"
              >
                <div className="min-w-0">
                  <p className="truncate font-bold text-zinc-950">{voucher.code}</p>
                  <p className="mt-1 truncate text-xs text-zinc-500">{usageLabel}</p>
                </div>
                <span className="h-fit rounded-full bg-amber-100 px-3 py-1 text-xs font-black text-amber-700">
                  {daysLeft != null ? `${daysLeft} hari` : "—"}
                </span>
              </div>
            );
          })
        ) : (
          <p className="rounded-lg bg-zinc-50 p-4 text-sm text-zinc-500">
            Tidak ada voucher yang akan expired.
          </p>
        )}
      </div>
    </section>
  );
}
