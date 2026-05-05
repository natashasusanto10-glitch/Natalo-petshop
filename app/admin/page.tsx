import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { getSession } from "@/lib/auth";
import { LogoutButton } from "@/components/LogoutButton";

export default async function AdminPage() {
  const session = await getSession();
  const [orders, products] = await Promise.all([
    prisma.order.findMany({
      orderBy: { createdAt: "desc" },
      take: 10,
    }),
    prisma.product.findMany({
      orderBy: { createdAt: "desc" },
      take: 20,
    }),
  ]);

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-zinc-950">Admin Toko</h1>
          <p className="mt-2 text-zinc-600">Masuk sebagai {session?.name ?? "Admin"}.</p>
        </div>

        <div className="flex items-center gap-3">
          <Link
            href="/admin/orders"
            className="rounded-full border border-zinc-300 px-5 py-3 text-sm font-bold"
          >
            Order
          </Link>
          <Link
            href="/admin/categories"
            className="rounded-full border border-zinc-300 px-5 py-3 text-sm font-bold"
          >
            Kategori
          </Link>
          <Link
            href="/admin/products"
            className="rounded-full border border-zinc-300 px-5 py-3 text-sm font-bold"
          >
            Produk
          </Link>
          <Link
            href="/products"
            className="rounded-full border border-zinc-300 px-5 py-3 text-sm font-bold"
          >
            Lihat toko
          </Link>
          <LogoutButton redirectTo="/admin/login" />
        </div>
      </div>

      <div className="mt-8 grid gap-6 lg:grid-cols-[1fr_420px]">
        <section className="rounded-3xl border border-zinc-200 p-5">
          <div className="flex items-center justify-between">
            <h2 className="font-bold text-zinc-950">Order terbaru</h2>
            <Link href="/admin/orders" className="text-xs font-bold text-zinc-500 hover:text-zinc-950">
              Lihat semua →
            </Link>
          </div>

          <div className="mt-4 space-y-3">
            {orders.length > 0 ? (
              orders.map((order) => (
                <Link
                  key={order.id}
                  href={`/admin/orders/${order.id}`}
                  className="block rounded-2xl bg-zinc-50 p-4 text-sm transition hover:bg-zinc-100"
                >
                  <div className="flex justify-between gap-4 font-semibold">
                    <span>{order.orderNumber}</span>
                    <span>{formatRupiah(order.total)}</span>
                  </div>
                  <p className="mt-1 text-zinc-600">
                    {order.customerName} • {order.paymentStatus} • {order.status}
                  </p>
                </Link>
              ))
            ) : (
              <p className="rounded-2xl bg-zinc-50 p-4 text-sm text-zinc-600">Belum ada order.</p>
            )}
          </div>
        </section>

        <section className="rounded-3xl border border-zinc-200 p-5">
          <h2 className="font-bold text-zinc-950">Produk</h2>

          <div className="mt-4 space-y-3">
            {products.length > 0 ? (
              products.map((product) => (
                <div
                  key={product.id}
                  className="flex justify-between gap-4 rounded-2xl bg-zinc-50 p-4 text-sm"
                >
                  <div>
                    <p className="font-semibold text-zinc-950">{product.name}</p>
                    <p className="mt-1 text-zinc-600">Stok {product.stock}</p>
                  </div>
                  <p className="font-bold text-zinc-950">
                    {formatRupiah(product.memberPrice ?? product.price)}
                  </p>
                </div>
              ))
            ) : (
              <p className="rounded-2xl bg-zinc-50 p-4 text-sm text-zinc-600">Belum ada produk.</p>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}
