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

  const STATUS_COLOR: Record<string, string> = {
    PENDING: "bg-orange-100 text-orange-600",
    PAID: "bg-blue-100 text-blue-600",
    PROCESSING: "bg-blue-100 text-blue-600",
    SHIPPED: "bg-indigo-100 text-indigo-600",
    DELIVERED: "bg-green-100 text-green-600",
    CANCELLED: "bg-red-100 text-red-500",
  };

  return (
    <div className="mx-auto max-w-4xl px-4 py-10">
      {/* Header member */}
      <div className="overflow-hidden rounded-3xl bg-orange-500 p-8 text-white">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="flex items-center gap-4">
            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-white/20 text-3xl font-black">
              {session?.name?.charAt(0)?.toUpperCase() ?? "🐾"}
            </div>
            <div>
              <p className="text-sm text-orange-100">Member resmi</p>
              <h1 className="mt-0.5 text-2xl font-black">Halo, {session?.name ?? "Member"}!</h1>
            </div>
          </div>
          <LogoutButton redirectTo="/member/login" className="border-white/30 text-white hover:border-white hover:text-white" />
        </div>
      </div>

      {/* Quick navigation */}
      <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { href: "/member/orders", icon: "📦", label: "Pesanan Saya" },
          { href: "/member/profile", icon: "👤", label: "Profil" },
          { href: "/wishlist", icon: "🤍", label: "Wishlist" },
          { href: "/order-status", icon: "🔍", label: "Cek Status" },
        ].map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className="flex flex-col items-center gap-2 rounded-2xl border border-gray-100 bg-white p-4 text-center shadow-sm transition hover:border-orange-200 hover:shadow-md"
          >
            <span className="text-2xl">{item.icon}</span>
            <span className="text-xs font-semibold text-gray-700">{item.label}</span>
          </Link>
        ))}
      </div>

      {/* Benefit cards */}
      <div className="mt-6 grid gap-4 sm:grid-cols-3">
        <div className="rounded-2xl border border-orange-100 bg-orange-50 p-5">
          <span className="text-2xl">🎟️</span>
          <p className="mt-2 font-bold text-gray-900">Voucher Member</p>
          <p className="mt-1 text-sm text-gray-500">Gunakan kode <span className="font-mono font-bold text-orange-600">MEMBER10</span> untuk diskon 10%.</p>
        </div>
        <div className="rounded-2xl border border-gray-100 bg-gray-50 p-5">
          <span className="text-2xl">⚡</span>
          <p className="mt-2 font-bold text-gray-900">Reorder Cepat</p>
          <p className="mt-1 text-sm text-gray-500">Beli ulang dari riwayat pesanan dengan sekali klik.</p>
        </div>
        <div className="rounded-2xl border border-gray-100 bg-gray-50 p-5">
          <span className="text-2xl">🔔</span>
          <p className="mt-2 font-bold text-gray-900">Notifikasi Order</p>
          <p className="mt-1 text-sm text-gray-500">Aktifkan push notification di halaman cek status pesanan.</p>
        </div>
      </div>

      {/* Order history */}
      <section className="mt-8">
        <div className="flex items-center justify-between">
          <h2 className="text-xl font-black text-gray-900">Pesanan Terbaru</h2>
          <Link href="/member/orders" className="text-sm font-semibold text-orange-500 hover:underline">
            Lihat semua →
          </Link>
        </div>

        <div className="mt-4 space-y-3">
          {orders.length > 0 ? (
            orders.map((order) => (
              <div key={order.id} className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <p className="font-bold text-gray-900">{order.orderNumber}</p>
                    <p className="mt-0.5 text-sm text-gray-400">
                      {order.items.length} produk · {formatRupiah(order.total)}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className={`rounded-full px-3 py-1 text-xs font-semibold ${STATUS_COLOR[order.status] ?? "bg-gray-100 text-gray-500"}`}>
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
