import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import Link from "next/link";
import { ReorderButton } from "@/components/ReorderButton";
import { requireCustomerSession } from "@/lib/session-guards";

const STATUS_LABEL: Record<string, string> = {
  PENDING: "Menunggu",
  PAID: "Dibayar",
  PROCESSING: "Diproses",
  SHIPPED: "Dikirim",
  DELIVERED: "Selesai",
  CANCELLED: "Dibatalkan",
  REFUNDED: "Refund",
};

const STATUS_COLOR: Record<string, string> = {
  PENDING: "bg-blue-100 text-blue-600",
  PAID: "bg-blue-100 text-blue-600",
  PROCESSING: "bg-blue-100 text-blue-600",
  SHIPPED: "bg-indigo-100 text-indigo-600",
  DELIVERED: "bg-green-100 text-green-600",
  CANCELLED: "bg-red-100 text-red-500",
  REFUNDED: "bg-zinc-100 text-zinc-500",
};

export default async function MemberOrdersPage() {
  const session = await requireCustomerSession();

  const orders = await prisma.order.findMany({
    where: { userId: session.sub },
    orderBy: { createdAt: "desc" },
    include: {
      items: {
        select: { name: true, quantity: true, price: true, productId: true },
      },
    },
  });

  return (
    <div className="mx-auto max-w-4xl px-4 py-4 md:py-10">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-black text-gray-900 md:text-2xl">
          Riwayat Pesanan
        </h1>
        <Link
          href="/member"
          className="text-sm font-semibold text-blue-500 hover:underline"
        >
          ← Kembali
        </Link>
      </div>

      <div className="mt-6 space-y-4">
        {orders.length > 0 ? (
          orders.map((order) => (
            <div
              key={order.id}
              className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="font-bold text-gray-900">{order.orderNumber}</p>
                  <p className="mt-0.5 text-sm text-gray-400">
                    {new Date(order.createdAt).toLocaleDateString("id-ID", {
                      day: "numeric",
                      month: "long",
                      year: "numeric",
                    })}
                  </p>
                </div>
                <span
                  className={`rounded-full px-3 py-1 text-xs font-semibold ${
                    STATUS_COLOR[order.status] ?? "bg-gray-100 text-gray-500"
                  }`}
                >
                  {STATUS_LABEL[order.status] ?? order.status}
                </span>
              </div>

              <div className="mt-3 space-y-1.5">
                {order.items.map((item, i) => (
                  <div
                    key={`${order.id}-${item.productId}-${i}`}
                    className="flex justify-between text-sm text-gray-600"
                  >
                    <span>
                      {item.name} × {item.quantity}
                    </span>
                    <span>{formatRupiah(item.price * item.quantity)}</span>
                  </div>
                ))}
              </div>

              <div className="mt-3 flex flex-wrap items-center justify-between gap-2 border-t pt-3">
                <span className="text-sm font-semibold text-gray-900">
                  Total: {formatRupiah(order.total)}
                </span>
                <div className="flex items-center gap-2">
                  <ReorderButton orderId={order.id} />
                  <Link
                    href={`/pesanan/${order.orderNumber}`}
                    className="rounded-full border border-gray-200 px-4 py-2 text-xs font-bold text-gray-700 transition hover:border-blue-400 hover:text-blue-500"
                  >
                    Detail →
                  </Link>
                </div>
              </div>
            </div>
          ))
        ) : (
          <div className="rounded-2xl border border-gray-100 bg-gray-50 p-12 text-center">
            <span className="text-5xl">🛒</span>
            <p className="mt-4 font-semibold text-gray-500">
              Belum ada pesanan.
            </p>
            <Link
              href="/products"
              className="mt-4 inline-flex rounded-full bg-blue-500 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-blue-600"
            >
              Mulai belanja
            </Link>
          </div>
        )}
      </div>
    </div>
  );
}
