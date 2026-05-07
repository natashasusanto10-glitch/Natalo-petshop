import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { getSession } from "@/lib/auth";

export default async function AdminPage() {
  const session = await getSession();
  const [orders, products, totalOrders, totalProducts, totalRevenue] = await Promise.all([
    prisma.order.findMany({
      orderBy: { createdAt: "desc" },
      take: 8,
    }),
    prisma.product.findMany({
      orderBy: { createdAt: "desc" },
      take: 10,
    }),
    prisma.order.count(),
    prisma.product.count(),
    prisma.order.aggregate({ _sum: { total: true }, where: { paymentStatus: "PAID" } }),
  ]);

  const stats = [
    { label: "Total Order", value: totalOrders, href: "/admin/orders", color: "bg-blue-50 text-blue-600" },
    { label: "Total Produk", value: totalProducts, href: "/admin/products", color: "bg-emerald-50 text-emerald-600" },
    {
      label: "Pendapatan",
      value: formatRupiah(totalRevenue._sum.total ?? 0),
      href: "/admin/reports",
      color: "bg-orange-50 text-orange-600",
    },
    {
      label: "Order Pending",
      value: orders.filter((o) => o.status === "PENDING").length,
      href: "/admin/orders?status=PENDING",
      color: "bg-amber-50 text-amber-600",
    },
  ];

  return (
    <div className="mx-auto max-w-6xl px-4 py-6 lg:py-10">
      <div>
        <h1 className="text-2xl font-black tracking-tight text-zinc-950 lg:text-3xl">Dashboard</h1>
        <p className="mt-1 text-sm text-zinc-500">Selamat datang, {session?.name ?? "Admin"}.</p>
      </div>

      {/* Stats */}
      <div className="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        {stats.map((stat) => (
          <Link
            key={stat.label}
            href={stat.href}
            className="rounded-2xl border border-zinc-100 bg-white p-4 transition hover:shadow-sm"
          >
            <p className="text-xs font-semibold text-zinc-500">{stat.label}</p>
            <p className={`mt-2 text-xl font-black ${stat.color.split(" ")[1]}`}>{stat.value}</p>
          </Link>
        ))}
      </div>

      <div className="mt-6 grid gap-5 lg:grid-cols-[1fr_360px]">
        {/* Recent orders */}
        <section className="rounded-3xl border border-zinc-200 bg-white p-5">
          <div className="flex items-center justify-between">
            <h2 className="font-bold text-zinc-950">Order Terbaru</h2>
            <Link href="/admin/orders" className="text-xs font-bold text-zinc-400 hover:text-zinc-950">
              Lihat semua →
            </Link>
          </div>

          <div className="mt-4 space-y-2">
            {orders.length > 0 ? (
              orders.map((order) => (
                <Link
                  key={order.id}
                  href={`/admin/orders/${order.id}`}
                  className="flex items-center justify-between rounded-xl bg-zinc-50 px-4 py-3 text-sm transition hover:bg-zinc-100"
                >
                  <div>
                    <p className="font-semibold text-zinc-900">{order.orderNumber}</p>
                    <p className="mt-0.5 text-xs text-zinc-500">{order.customerName}</p>
                  </div>
                  <div className="text-right">
                    <p className="font-bold text-zinc-950">{formatRupiah(order.total)}</p>
                    <p className="mt-0.5 text-xs text-zinc-400">{order.status}</p>
                  </div>
                </Link>
              ))
            ) : (
              <p className="rounded-xl bg-zinc-50 p-4 text-sm text-zinc-500">Belum ada order.</p>
            )}
          </div>
        </section>

        {/* Recent products */}
        <section className="rounded-3xl border border-zinc-200 bg-white p-5">
          <div className="flex items-center justify-between">
            <h2 className="font-bold text-zinc-950">Produk Terbaru</h2>
            <Link href="/admin/products" className="text-xs font-bold text-zinc-400 hover:text-zinc-950">
              Lihat semua →
            </Link>
          </div>

          <div className="mt-4 space-y-2">
            {products.length > 0 ? (
              products.map((product) => (
                <div
                  key={product.id}
                  className="flex items-center justify-between rounded-xl bg-zinc-50 px-4 py-3 text-sm"
                >
                  <div className="min-w-0">
                    <p className="truncate font-semibold text-zinc-900">{product.name}</p>
                    <p className="mt-0.5 text-xs text-zinc-500">Stok: {product.stock}</p>
                  </div>
                  <p className="ml-3 shrink-0 font-bold text-zinc-950">
                    {formatRupiah(product.memberPrice ?? product.price)}
                  </p>
                </div>
              ))
            ) : (
              <p className="rounded-xl bg-zinc-50 p-4 text-sm text-zinc-500">Belum ada produk.</p>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}
