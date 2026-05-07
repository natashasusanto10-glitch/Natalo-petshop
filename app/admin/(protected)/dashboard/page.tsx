import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { getSession } from "@/lib/auth";
import { LogoutButton } from "@/components/LogoutButton";
import { AdminInstallPrompt } from "@/components/AdminInstallPrompt";

const STATUS_LABELS: Record<string, string> = {
  PENDING: "Order Baru",
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

function startOfToday() {
  const date = new Date();
  date.setHours(0, 0, 0, 0);
  return date;
}

function endOfToday() {
  const date = new Date();
  date.setHours(23, 59, 59, 999);
  return date;
}

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
  const session = await getSession();
  const todayStart = startOfToday();
  const todayEnd = endOfToday();

  const [
    orderStatusCounts,
    waitingPaymentCount,
    newOrdersTodayCount,
    todaySales,
    actionOrders,
    lowStockProducts,
    outOfStockProducts,
  ] = await Promise.all([
    prisma.order.groupBy({ by: ["status"], _count: true }),
    prisma.order.count({
      where: { paymentStatus: { in: ["UNPAID", "PENDING"] }, status: { notIn: ["CANCELLED", "REFUNDED"] } },
    }),
    prisma.order.count({
      where: { createdAt: { gte: todayStart, lte: todayEnd } },
    }),
    prisma.order.aggregate({
      where: {
        createdAt: { gte: todayStart, lte: todayEnd },
        paymentStatus: "PAID",
        status: { notIn: ["CANCELLED", "REFUNDED"] },
      },
      _sum: { total: true },
    }),
    prisma.order.findMany({
      where: {
        OR: [
          { status: "PENDING" },
          { status: "PROCESSING" },
          { status: "SHIPPED" },
          { paymentStatus: { in: ["UNPAID", "PENDING"] }, status: { notIn: ["CANCELLED", "DELIVERED", "REFUNDED"] } },
        ],
      },
      orderBy: { createdAt: "desc" },
      take: 8,
      include: { items: { select: { quantity: true } } },
    }),
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
  ]);

  const countMap: Record<string, number> = {};
  for (const row of orderStatusCounts) countMap[row.status] = row._count;

  const stats = [
    {
      label: "Order Baru",
      value: newOrdersTodayCount,
      helper: "Masuk hari ini",
      href: "/admin/orders",
    },
    {
      label: "Menunggu Pembayaran",
      value: waitingPaymentCount,
      helper: "Belum lunas / verifikasi",
      href: "/admin/orders?pay=PENDING",
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
      value: lowStockProducts.length,
      helper: `Stok 1-${LOW_STOCK_LIMIT}`,
      href: "/admin/products",
    },
    {
      label: "Produk Habis",
      value: outOfStockProducts.length,
      helper: "Stok 0",
      href: "/admin/products",
    },
  ];

  return (
    <div className="mx-auto max-w-7xl px-4 py-8">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-zinc-950">
            Dashboard Admin
          </h1>
          <p className="mt-2 text-sm text-zinc-600">
            Masuk sebagai {session?.name ?? "Admin"}. Fokus utama: order masuk dan stok kritis.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <AdminNavLink href="/admin/orders">Order</AdminNavLink>
          <AdminNavLink href="/admin/products">Produk</AdminNavLink>
          <AdminNavLink href="/admin/vouchers">Voucher</AdminNavLink>
          <AdminNavLink href="/admin/reviews">Review</AdminNavLink>
          <LogoutButton redirectTo="/admin/login" />
        </div>
      </div>

      <section className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {stats.map((stat) => (
          <Link
            key={stat.label}
            href={stat.href}
            className="rounded-lg border border-zinc-200 bg-white p-4 transition hover:border-zinc-400"
          >
            <p className="text-xs font-bold uppercase tracking-wide text-zinc-500">{stat.label}</p>
            <p className="mt-3 text-3xl font-black text-zinc-950">{stat.value}</p>
            <p className="mt-1 text-xs font-medium text-zinc-500">{stat.helper}</p>
          </Link>
        ))}
      </section>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_360px]">
        <section className="rounded-lg border border-zinc-200 bg-white p-5">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h2 className="text-lg font-black text-zinc-950">Order Perlu Diproses</h2>
              <p className="mt-1 text-sm text-zinc-500">
                Prioritas: pembayaran menunggu, order baru, packing, dan pengiriman.
              </p>
            </div>
            <Link href="/admin/orders" className="text-sm font-bold text-zinc-600 hover:text-zinc-950">
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
        </aside>
      </div>
    </div>
  );
}

function AdminNavLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-bold text-zinc-700 hover:border-zinc-500"
    >
      {children}
    </Link>
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
