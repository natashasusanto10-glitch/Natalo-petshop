import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";

const STATUS_LABELS: Record<string, string> = {
  NEED_PACKING: "Siap packing",
  PENDING: "Order Baru",
  PAID: "Sudah Dibayar",
  PROCESSING: "Diproses",
  READY_FOR_PICKUP: "Siap Diambil",
  SHIPPED: "Dikirim",
  DELIVERED: "Selesai",
  CANCELLED: "Dibatalkan",
  REFUNDED: "Refund",
};

const STATUS_COLORS: Record<string, string> = {
  NEED_PACKING: "bg-emerald-100 text-emerald-700",
  PENDING: "bg-amber-100 text-amber-700",
  PAID: "bg-emerald-100 text-emerald-700",
  PROCESSING: "bg-natalo-100 text-natalo-700",
  READY_FOR_PICKUP: "bg-green-100 text-green-700",
  SHIPPED: "bg-indigo-100 text-indigo-700",
  DELIVERED: "bg-emerald-100 text-emerald-700",
  CANCELLED: "bg-red-100 text-red-700",
  REFUNDED: "bg-zinc-100 text-zinc-600",
};

const PAY_LABELS: Record<string, string> = {
  WAITING: "Menunggu bayar",
  UNPAID: "Belum bayar",
  PENDING: "Menunggu",
  PAID: "Lunas",
  FAILED: "Gagal",
  EXPIRED: "Kedaluwarsa",
  REFUNDED: "Refund",
};

const PAY_COLORS: Record<string, string> = {
  WAITING: "bg-amber-100 text-amber-700",
  UNPAID: "bg-red-100 text-red-700",
  PENDING: "bg-amber-100 text-amber-700",
  PAID: "bg-green-100 text-green-700",
  FAILED: "bg-red-100 text-red-700",
  EXPIRED: "bg-zinc-100 text-zinc-600",
  REFUNDED: "bg-zinc-100 text-zinc-600",
};

const PAGE_SIZE = 20;

export default async function AdminOrdersPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; pay?: string; type?: string; page?: string }>;
}) {
  const { status, pay, type, page: pageStr } = await searchParams;
  const page = Math.max(1, parseInt(pageStr || "1", 10));

  const where: Record<string, unknown> = {};
  if (status === "NEED_PACKING") {
    where.status = { in: ["PENDING", "PAID", "PROCESSING"] };
    where.paymentStatus = "PAID";
  } else if (status && status !== "ALL") {
    where.status = status;
  }

  if (type === "SELF_PICKUP") {
    where.orderType = "SELF_PICKUP";
  } else if (type === "DELIVERY") {
    where.orderType = "DELIVERY";
  }

  if (status === "NEED_PACKING") {
    // Filter khusus ini sudah mendefinisikan status dan pembayaran.
  } else if (pay === "WAITING") {
    where.paymentStatus = { in: ["UNPAID", "PENDING"] };
  } else if (pay && pay !== "ALL") {
    where.paymentStatus = pay;
  }

  const [orders, total, statusCounts, needPackingCount] = await Promise.all([
    prisma.order.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * PAGE_SIZE,
      take: PAGE_SIZE,
      include: { items: { select: { quantity: true } } },
    }),
    prisma.order.count({ where }),
    prisma.order.groupBy({ by: ["status"], _count: true }),
    prisma.order.count({
      where: { paymentStatus: "PAID", status: { in: ["PENDING", "PAID", "PROCESSING"] } },
    }),
  ]);

  const totalPages = Math.ceil(total / PAGE_SIZE);
  const countMap: Record<string, number> = {};
  for (const s of statusCounts) countMap[s.status] = s._count;
  const totalCount = Object.values(countMap).reduce((a, b) => a + b, 0);

  function buildUrl(overrides: Record<string, string>) {
    const sp = new URLSearchParams();
    const merged: Record<string, string> = {
      status: status || "ALL",
      pay: pay || "ALL",
      type: type || "ALL",
      page: "1",
      ...overrides,
    };
    if (merged.status && merged.status !== "ALL") sp.set("status", merged.status);
    if (merged.pay && merged.pay !== "ALL") sp.set("pay", merged.pay);
    if (merged.type && merged.type !== "ALL") sp.set("type", merged.type);
    if (merged.page && merged.page !== "1") sp.set("page", merged.page);
    const str = sp.toString();
    return `/admin/orders${str ? `?${str}` : ""}`;
  }

  const tabs = [
    { key: "ALL", label: "Semua", count: totalCount },
    { key: "NEED_PACKING", label: "Siap packing", count: needPackingCount },
    { key: "PENDING", label: "Order Baru", count: countMap["PENDING"] ?? 0 },
    { key: "PAID", label: "Sudah Dibayar", count: countMap["PAID"] ?? 0 },
    { key: "PROCESSING", label: "Diproses", count: countMap["PROCESSING"] ?? 0 },
    { key: "READY_FOR_PICKUP", label: "Siap Diambil", count: countMap["READY_FOR_PICKUP"] ?? 0 },
    { key: "SHIPPED", label: "Dikirim", count: countMap["SHIPPED"] ?? 0 },
    { key: "DELIVERED", label: "Selesai", count: countMap["DELIVERED"] ?? 0 },
    { key: "CANCELLED", label: "Dibatalkan", count: countMap["CANCELLED"] ?? 0 },
    { key: "REFUNDED", label: "Refund", count: countMap["REFUNDED"] ?? 0 },
  ];

  const activeStatus = status || "ALL";
  const activePay = pay || "ALL";
  const activeType = type || "ALL";

  return (
    <div className="mx-auto max-w-6xl px-4 py-5 md:py-10">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <Link href="/admin" className="hidden text-sm font-bold text-zinc-500 hover:text-zinc-950 md:inline">
            ← Kembali ke admin
          </Link>
          <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:mt-2 md:text-3xl">Manajemen Order</h1>
          <p className="mt-1 text-sm text-zinc-500">{total} order ditemukan</p>
        </div>
      </div>

      {/* Type tabs */}
      <div className="-mx-4 mt-5 flex gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:mt-8 md:flex-wrap md:overflow-visible md:px-0">
        {[
          { key: "ALL", label: "Semua" },
          { key: "DELIVERY", label: "Delivery" },
          { key: "SELF_PICKUP", label: "Self Pick Up" },
        ].map((tab) => (
          <Link
            key={tab.key}
            href={buildUrl({ type: tab.key })}
            className={`inline-flex shrink-0 items-center gap-2 rounded-full px-4 py-2 text-sm font-bold transition ${
              activeType === tab.key
                ? "bg-natalo-600 text-white"
                : "border border-zinc-200 text-zinc-600 hover:border-zinc-400"
            }`}
          >
            {tab.label}
          </Link>
        ))}
      </div>

      {/* Status tabs */}
      <div className="-mx-4 mt-3 flex gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:mt-4 md:flex-wrap md:overflow-visible md:px-0">
        {tabs.map((tab) => (
          <Link
            key={tab.key}
            href={buildUrl({ status: tab.key })}
            className={`inline-flex shrink-0 items-center gap-2 rounded-full px-4 py-2 text-sm font-bold transition ${
              activeStatus === tab.key
                ? "bg-zinc-950 text-white"
                : "border border-zinc-200 text-zinc-600 hover:border-zinc-400"
            }`}
          >
            {tab.label}
            <span
              className={`rounded-full px-2 py-0.5 text-xs font-black ${
                activeStatus === tab.key ? "bg-white/20 text-white" : "bg-zinc-100 text-zinc-600"
              }`}
            >
              {tab.count}
            </span>
          </Link>
        ))}
      </div>

      {/* Payment filter */}
      <div className="-mx-4 mt-3 flex items-center gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:mt-4 md:flex-wrap md:overflow-visible md:px-0">
        <span className="shrink-0 text-xs font-semibold text-zinc-500">Pembayaran:</span>
        {(["ALL", "WAITING", "UNPAID", "PENDING", "PAID", "FAILED", "EXPIRED"] as const).map((p) => (
          <Link
            key={p}
            href={buildUrl({ pay: p })}
            className={`shrink-0 rounded-full px-3 py-1 text-xs font-bold transition ${
              activePay === p
                ? "bg-zinc-950 text-white"
                : "border border-zinc-200 text-zinc-600 hover:border-zinc-400"
            }`}
          >
            {p === "ALL" ? "Semua" : PAY_LABELS[p]}
          </Link>
        ))}
      </div>

      {/* Empty state */}
      {orders.length === 0 ? (
        <div className="mt-6 overflow-hidden rounded-2xl border border-zinc-200 p-12 text-center text-sm text-zinc-500 md:rounded-3xl">
          <p className="text-2xl">📦</p>
          <p className="mt-3 font-semibold text-zinc-700">Tidak ada order</p>
          <p className="mt-1">Coba ganti filter di atas.</p>
        </div>
      ) : (
        <>
          {/* Mobile card list */}
          <div className="mt-5 space-y-3 md:hidden">
            {orders.map((order) => {
              const totalQty = order.items.reduce((s, i) => s + i.quantity, 0);
              return (
                <Link
                  key={order.id}
                  href={`/admin/orders/${order.id}`}
                  className="block rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm transition active:scale-[0.99]"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate font-black text-zinc-950">{order.orderNumber}</p>
                      <p className="mt-0.5 text-xs text-zinc-500">
                        {new Date(order.createdAt).toLocaleString("id-ID", {
                          day: "numeric",
                          month: "short",
                          hour: "2-digit",
                          minute: "2-digit",
                        })}
                      </p>
                    </div>
                    <span className="shrink-0 text-base font-black text-zinc-950">
                      {formatRupiah(order.total)}
                    </span>
                  </div>

                  <div className="mt-2.5 flex items-center justify-between gap-3 text-sm">
                    <div className="min-w-0">
                      <p className="truncate font-semibold text-zinc-800">{order.customerName}</p>
                      <p className="truncate text-xs text-zinc-500">{order.customerPhone}</p>
                    </div>
                    <span className="shrink-0 text-[11px] font-bold text-zinc-500">
                      {totalQty} item · {order.orderType === "SELF_PICKUP" ? "Pickup" : "Delivery"}
                    </span>
                  </div>

                  <div className="mt-3 flex flex-wrap gap-1.5">
                    <span
                      className={`rounded-full px-2.5 py-0.5 text-[11px] font-bold ${
                        STATUS_COLORS[order.status] ?? "bg-zinc-100 text-zinc-600"
                      }`}
                    >
                      {STATUS_LABELS[order.status] ?? order.status}
                    </span>
                    <span
                      className={`rounded-full px-2.5 py-0.5 text-[11px] font-bold ${
                        PAY_COLORS[order.paymentStatus] ?? "bg-zinc-100 text-zinc-600"
                      }`}
                    >
                      {PAY_LABELS[order.paymentStatus] ?? order.paymentStatus}
                    </span>
                  </div>
                </Link>
              );
            })}
          </div>

          {/* Desktop table */}
          <div className="mt-6 hidden overflow-hidden rounded-3xl border border-zinc-200 md:block">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-zinc-100 bg-zinc-50">
                    <th className="px-5 py-4 text-left font-semibold text-zinc-600">Order</th>
                    <th className="px-5 py-4 text-left font-semibold text-zinc-600">Customer</th>
                    <th className="px-5 py-4 text-left font-semibold text-zinc-600">Total</th>
                    <th className="px-5 py-4 text-left font-semibold text-zinc-600">Pembayaran</th>
                    <th className="px-5 py-4 text-left font-semibold text-zinc-600">Status</th>
                    <th className="px-5 py-4 text-left font-semibold text-zinc-600 hidden lg:table-cell">
                      Tanggal
                    </th>
                    <th className="px-5 py-4" />
                  </tr>
                </thead>
                <tbody>
                  {orders.map((order) => {
                    const totalQty = order.items.reduce((s, i) => s + i.quantity, 0);
                    return (
                      <tr
                        key={order.id}
                        className="border-b border-zinc-100 last:border-0 hover:bg-zinc-50 transition"
                      >
                        <td className="px-5 py-4">
                          <p className="font-bold text-zinc-950">{order.orderNumber}</p>
                          <p className="text-zinc-400">{totalQty} item</p>
                          <p className="mt-1 text-xs font-bold text-zinc-500">
                            {order.orderType === "SELF_PICKUP"
                              ? "Ambil Sendiri di Toko"
                              : "Delivery"}
                          </p>
                        </td>
                        <td className="px-5 py-4">
                          <p className="font-semibold text-zinc-950">{order.customerName}</p>
                          <p className="text-zinc-400">{order.customerPhone}</p>
                        </td>
                        <td className="px-5 py-4">
                          <span className="font-bold text-zinc-950">
                            {formatRupiah(order.total)}
                          </span>
                        </td>
                        <td className="px-5 py-4">
                          <span
                            className={`rounded-full px-3 py-1 text-xs font-bold ${
                              PAY_COLORS[order.paymentStatus] ?? "bg-zinc-100 text-zinc-600"
                            }`}
                          >
                            {PAY_LABELS[order.paymentStatus] ?? order.paymentStatus}
                          </span>
                        </td>
                        <td className="px-5 py-4">
                          <span
                            className={`rounded-full px-3 py-1 text-xs font-bold ${
                              STATUS_COLORS[order.status] ?? "bg-zinc-100 text-zinc-600"
                            }`}
                          >
                            {STATUS_LABELS[order.status] ?? order.status}
                          </span>
                        </td>
                        <td className="px-5 py-4 text-zinc-400 hidden lg:table-cell">
                          {new Date(order.createdAt).toLocaleDateString("id-ID", {
                            day: "numeric",
                            month: "short",
                            year: "numeric",
                          })}
                        </td>
                        <td className="px-5 py-4">
                          <Link
                            href={`/admin/orders/${order.id}`}
                            className="rounded-full border border-zinc-200 px-3 py-1.5 text-xs font-bold hover:border-zinc-400 transition"
                          >
                            Detail
                          </Link>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="mt-5 flex items-center justify-between gap-3 md:mt-6">
          <p className="text-sm text-zinc-500">
            Hal. {page}/{totalPages}
          </p>
          <div className="flex gap-2">
            {page > 1 && (
              <Link
                href={buildUrl({ page: String(page - 1) })}
                className="rounded-full border border-zinc-200 px-4 py-2 text-sm font-bold hover:border-zinc-400"
              >
                ← Sebelumnya
              </Link>
            )}
            {page < totalPages && (
              <Link
                href={buildUrl({ page: String(page + 1) })}
                className="rounded-full bg-zinc-950 px-4 py-2 text-sm font-bold text-white"
              >
                Berikutnya →
              </Link>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
