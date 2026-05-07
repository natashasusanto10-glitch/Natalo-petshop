import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { LogoutButton } from "@/components/LogoutButton";
import { MemberNav } from "@/components/MemberNav";
import { ReorderButton } from "@/components/ReorderButton";
import { EmptyOrders } from "@/components/LoadingEmptyStates";
import Link from "next/link";

const STATUS_LABEL: Record<string, string> = {
  PENDING: "Menunggu",
  PROCESSING: "Diproses",
  SHIPPED: "Dikirim",
  DELIVERED: "Selesai",
  CANCELLED: "Dibatalkan",
  REFUNDED: "Refund",
};

const STATUS_COLOR: Record<string, string> = {
  PENDING: "bg-amber-100 text-amber-700",
  PROCESSING: "bg-natalo-100 text-natalo-700",
  SHIPPED: "bg-indigo-100 text-indigo-700",
  DELIVERED: "bg-emerald-100 text-emerald-700",
  CANCELLED: "bg-red-100 text-red-600",
  REFUNDED: "bg-zinc-100 text-zinc-600",
};

const PAY_LABEL: Record<string, string> = {
  UNPAID: "Belum bayar",
  PENDING: "Menunggu verifikasi",
  PAID: "Lunas",
  FAILED: "Gagal",
  EXPIRED: "Kedaluwarsa",
  REFUNDED: "Refund",
};

const PAGE_SIZE = 10;

export default async function MemberOrdersPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; page?: string }>;
}) {
  const session = await getSession();
  const { status, page: pageStr } = await searchParams;
  const page = Math.max(1, parseInt(pageStr || "1", 10));

  const where: Record<string, unknown> = { userId: session?.sub };
  if (status && status !== "ALL") where.status = status;

  const [orders, total] = await Promise.all([
    prisma.order.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * PAGE_SIZE,
      take: PAGE_SIZE,
      include: {
        items: {
          select: {
            id: true,
            quantity: true,
            name: true,
            price: true,
            variantLabel: true,
            product: { select: { imageUrl: true, slug: true } },
          },
        },
      },
    }),
    prisma.order.count({ where }),
  ]);

  const totalPages = Math.ceil(total / PAGE_SIZE);

  function buildUrl(overrides: Record<string, string>) {
    const sp = new URLSearchParams();
    const merged = { status: status || "ALL", page: "1", ...overrides };
    if (merged.status && merged.status !== "ALL") sp.set("status", merged.status);
    if (merged.page && merged.page !== "1") sp.set("page", merged.page);
    const str = sp.toString();
    return `/member/orders${str ? `?${str}` : ""}`;
  }

  const tabs = [
    { key: "ALL", label: "Semua" },
    { key: "PENDING", label: "Menunggu" },
    { key: "PROCESSING", label: "Diproses" },
    { key: "SHIPPED", label: "Dikirim" },
    { key: "DELIVERED", label: "Selesai" },
    { key: "CANCELLED", label: "Dibatalkan" },
  ];

  const activeStatus = status || "ALL";

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-natalo-600 px-4 pb-0 pt-8">
        <div className="mx-auto max-w-4xl">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-white/20 text-2xl">
                🐾
              </div>
              <div>
                <p className="text-xs text-natalo-100">Member resmi</p>
                <p className="text-lg font-black text-white">Halo, {session?.name}!</p>
              </div>
            </div>
            <LogoutButton redirectTo="/member/login" className="border-white/30 text-white hover:border-white/60" />
          </div>
          <MemberNav />
        </div>
      </div>

      <main className="mx-auto max-w-4xl px-4 py-8">
        <h2 className="text-xl font-black text-gray-900">Riwayat Pesanan</h2>
        <p className="mt-1 text-sm text-gray-500">{total} pesanan ditemukan</p>

        {/* Status filter */}
        <div className="mt-5 flex flex-wrap gap-2">
          {tabs.map((tab) => (
            <Link
              key={tab.key}
              href={buildUrl({ status: tab.key })}
              className={`rounded-full px-4 py-2 text-sm font-bold transition ${
                activeStatus === tab.key
                  ? "bg-natalo-600 text-white"
                  : "border border-gray-200 bg-white text-gray-600 hover:border-natalo-300"
              }`}
            >
              {tab.label}
            </Link>
          ))}
        </div>

        {/* Orders list */}
        <div className="mt-5 space-y-4">
          {orders.length === 0 ? (
            <div className="rounded-2xl border border-gray-100 bg-white">
              <EmptyOrders filtered={activeStatus !== "ALL"} />
            </div>
          ) : (
            orders.map((order) => {
              const totalQty = order.items.reduce((s, i) => s + i.quantity, 0);
              return (
                <div
                  key={order.id}
                  className="overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm"
                >
                  {/* Order header */}
                  <div className="flex flex-wrap items-center justify-between gap-3 border-b border-gray-100 p-4">
                    <div>
                      <p className="font-bold text-gray-900">{order.orderNumber}</p>
                      <p className="mt-0.5 text-xs text-gray-400">
                        {new Date(order.createdAt).toLocaleDateString("id-ID", {
                          day: "numeric",
                          month: "long",
                          year: "numeric",
                        })}
                      </p>
                    </div>
                    <div className="flex items-center gap-2">
                      <span
                        className={`rounded-full px-3 py-1 text-xs font-bold ${
                          STATUS_COLOR[order.status] ?? "bg-zinc-100 text-zinc-600"
                        }`}
                      >
                        {STATUS_LABEL[order.status] ?? order.status}
                      </span>
                      <span className="text-xs text-gray-400">
                        {PAY_LABEL[order.paymentStatus] ?? order.paymentStatus}
                      </span>
                    </div>
                  </div>

                  {/* Items detail dengan tombol Beli Lagi per item */}
                  <div className="divide-y divide-gray-100">
                    {order.items.map((item) => (
                      <div key={item.id} className="flex gap-3 p-4">
                        <div className="h-14 w-14 shrink-0 overflow-hidden rounded-lg bg-gray-100">
                          {item.product.imageUrl ? (
                            // eslint-disable-next-line @next/next/no-img-element
                            <img
                              src={item.product.imageUrl}
                              alt={item.name}
                              className="h-full w-full object-cover"
                            />
                          ) : (
                            <div className="flex h-full items-center justify-center text-2xl">
                              🐾
                            </div>
                          )}
                        </div>
                        <div className="flex-1 min-w-0">
                          <Link
                            href={`/products/${item.product.slug}`}
                            className="line-clamp-2 text-sm font-semibold text-gray-900 hover:text-natalo-700"
                          >
                            {item.name}
                          </Link>
                          {item.variantLabel && (
                            <p className="mt-0.5 text-xs font-medium text-natalo-600">
                              {item.variantLabel}
                            </p>
                          )}
                          <p className="mt-0.5 text-xs text-gray-500">
                            {formatRupiah(item.price)} × {item.quantity}
                          </p>
                        </div>
                        <div className="flex shrink-0 items-start">
                          <ReorderButton
                            orderNumber={order.orderNumber}
                            itemId={item.id}
                            variant="ghost"
                          >
                            🔄 Beli Lagi
                          </ReorderButton>
                        </div>
                      </div>
                    ))}
                  </div>

                  {/* Footer order: total + actions */}
                  <div className="flex flex-wrap items-center justify-between gap-3 border-t border-gray-100 bg-gray-50 p-4">
                    <div>
                      <p className="text-xs text-gray-500">{totalQty} produk • Total</p>
                      <p className="font-black text-gray-900">{formatRupiah(order.total)}</p>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      <ReorderButton
                        orderNumber={order.orderNumber}
                        variant="primary"
                      >
                        🔄 Pesan Semua Lagi
                      </ReorderButton>
                      <Link
                        href={`/order-status?order=${order.orderNumber}`}
                        className="rounded-full border border-gray-300 bg-white px-4 py-2.5 text-sm font-bold text-gray-700 hover:border-natalo-300 hover:text-natalo-600"
                      >
                        Detail
                      </Link>
                    </div>
                  </div>
                </div>
              );
            })
          )}
        </div>

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="mt-6 flex items-center justify-between">
            <p className="text-sm text-gray-500">
              Halaman {page} dari {totalPages}
            </p>
            <div className="flex gap-2">
              {page > 1 && (
                <Link
                  href={buildUrl({ page: String(page - 1) })}
                  className="rounded-full border border-gray-200 px-4 py-2 text-sm font-bold hover:border-gray-400"
                >
                  ← Sebelumnya
                </Link>
              )}
              {page < totalPages && (
                <Link
                  href={buildUrl({ page: String(page + 1) })}
                  className="rounded-full bg-natalo-600 px-4 py-2 text-sm font-bold text-white hover:bg-natalo-700"
                >
                  Berikutnya →
                </Link>
              )}
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
