import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { LogoutButton } from "@/components/LogoutButton";
import Link from "next/link";

export default async function MemberPage() {
  const session = await getSession();

  const orders = session
    ? await prisma.order.findMany({
        where: { userId: session.sub },
        orderBy: { createdAt: "desc" },
        take: 5,
        include: { items: true },
      })
    : [];

  const STATUS_LABEL: Record<string, string> = {
    PENDING: "Menunggu",
    PAID: "Dibayar",
    PROCESSING: "Diproses",
    SHIPPED: "Dikirim",
    DELIVERED: "Selesai",
    CANCELLED: "Dibatalkan",
  };

  return (
    <div className="mx-auto max-w-4xl px-4 py-10">
      {/* Header member */}
      <div className="overflow-hidden rounded-3xl bg-orange-500 p-8 text-white">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="flex items-center gap-4">
            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-white/20 text-3xl">
              🐾
            </div>
            <div>
              <p className="text-sm text-orange-100">Member resmi</p>
              <h1 className="mt-0.5 text-2xl font-black">Halo, {session?.name}!</h1>
            </div>
          </div>
          <LogoutButton redirectTo="/member/login" className="border-white/30 text-white hover:border-white hover:text-white" />
        </div>
      </div>

      {/* Benefit cards */}
      <div className="mt-6 grid gap-4 sm:grid-cols-3">
        <div className="rounded-2xl border border-orange-100 bg-orange-50 p-5">
          <span className="text-2xl">🎟️</span>
          <p className="mt-2 font-bold text-gray-900">Voucher Member</p>
          <p className="mt-1 text-sm text-gray-500">Gunakan kode MEMBER10 untuk diskon 10% pembelian pertama.</p>
        </div>
        <div className="rounded-2xl border border-gray-100 bg-gray-50 p-5">
          <span className="text-2xl">⚡</span>
          <p className="mt-2 font-bold text-gray-900">Reorder Cepat</p>
          <p className="mt-1 text-sm text-gray-500">Beli ulang produk favorit dari riwayat pesanan dengan mudah.</p>
        </div>
        <div className="rounded-2xl border border-gray-100 bg-gray-50 p-5">
          <span className="text-2xl">🔔</span>
          <p className="mt-2 font-bold text-gray-900">Info Restock</p>
          <p className="mt-1 text-sm text-gray-500">Dapat kabar restock dan promo eksklusif lebih awal.</p>
        </div>
      </div>

      {/* Order history */}
      <section className="mt-8">
        <h2 className="font-black text-gray-900 text-xl">Riwayat Pesanan</h2>

        <div className="mt-4 space-y-3">
          {orders.length > 0 ? (
            orders.map((order) => (
              <div key={order.id} className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <p className="font-bold text-gray-900">{order.orderNumber}</p>
                    <p className="mt-0.5 text-sm text-gray-400">
                      {order.items.length} produk • {formatRupiah(order.total)}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className={`rounded-full px-3 py-1 text-xs font-semibold ${
                      order.status === "DELIVERED" ? "bg-green-100 text-green-600" :
                      order.status === "SHIPPED" ? "bg-blue-100 text-blue-600" :
                      order.status === "CANCELLED" ? "bg-red-100 text-red-500" :
                      "bg-orange-100 text-orange-600"
                    }`}>
                      {STATUS_LABEL[order.status] ?? order.status}
                    </span>
                    <Link
                      href={`/order-status?order=${order.orderNumber}`}
                      className="text-sm font-semibold text-orange-500 hover:underline"
                    >
                      Detail →
                    </Link>
                  </div>
                </div>
              </div>
            ))
          ) : (
            <div className="rounded-2xl border border-gray-100 bg-gray-50 p-8 text-center">
              <span className="text-4xl">🛒</span>
              <p className="mt-3 text-sm text-gray-500">Belum ada pesanan.</p>
              <Link
                href="/products"
                className="mt-4 inline-flex rounded-full bg-orange-500 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-orange-600"
              >
                Mulai belanja
              </Link>
            </div>
          )}
        </div>
      </section>
    </div>
  );
}
