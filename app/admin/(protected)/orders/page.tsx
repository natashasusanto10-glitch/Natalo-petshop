import Link from "next/link";
import Image from "next/image";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import {
  PageHeader,
  EmptyState,
  Badge,
  Button,
  AdminPage,
  STATUS_BADGE_VARIANT,
  PAY_BADGE_VARIANT,
  type BadgeVariant,
} from "@/components/admin/ui";
import { orderStatusLabel, paymentStatusLabel } from "@/lib/order-labels";

// Special variant override untuk NEED_PACKING (bukan order.status real, tapi
// filter combine PAID + status ∈ {PENDING,PAID,PROCESSING}). Treat as success.
// Explicit type biar TS gak narrow ke literal saat spread.
const EXTRA_STATUS_VARIANT: Record<string, BadgeVariant> = {
  ...STATUS_BADGE_VARIANT,
  NEED_PACKING: "success",
};

const EXTRA_PAY_VARIANT: Record<string, BadgeVariant> = {
  ...PAY_BADGE_VARIANT,
  WAITING: "warning",
};

const CTA_PILL_CLASSES: Record<string, string> = {
  primary: "bg-natalo-600 text-white",
  secondary: "bg-zinc-100 text-zinc-700",
  dangerSoft: "bg-red-50 text-red-700 ring-1 ring-inset ring-red-200",
};

/**
 * Label/tombol aksi sadar-status pesanan. SEMUA mengarah ke halaman Detail
 * (aksi dieksekusi di sana), tapi label + warna mencerminkan langkah
 * berikutnya supaya admin tahu apa yang harus dilakukan tanpa membuka detail.
 */
function orderCtaLabel(order: {
  status: string;
  paymentStatus: string;
  orderType: string;
  cancellationRequestStatus: string | null;
}): { label: string; variant: "primary" | "secondary" | "dangerSoft" } {
  if (order.cancellationRequestStatus === "PENDING")
    return { label: "Tinjau Pembatalan", variant: "dangerSoft" };
  if (
    order.status === "DELIVERED" ||
    order.status === "CANCELLED" ||
    order.status === "REFUNDED"
  )
    return { label: "Lihat Detail", variant: "secondary" };
  if (order.paymentStatus !== "PAID")
    return { label: "Cek Bukti & Konfirmasi", variant: "primary" };
  if (order.status === "PENDING" || order.status === "PAID")
    return { label: "Mulai Packing", variant: "primary" };
  if (order.status === "PROCESSING")
    return order.orderType === "SELF_PICKUP"
      ? { label: "Siap Diambil", variant: "primary" }
      : { label: "Input Resi & Kirim", variant: "primary" };
  if (order.status === "READY_FOR_PICKUP")
    return { label: "Serahkan", variant: "primary" };
  if (order.status === "SHIPPED")
    return { label: "Lihat / Lacak", variant: "secondary" };
  return { label: "Lihat Detail", variant: "secondary" };
}

/** Thumbnail produk (item pertama) untuk baris pesanan, dengan placeholder. */
function OrderThumb({
  url,
  className = "h-10 w-10",
}: {
  url: string | null;
  className?: string;
}) {
  return (
    <div className={`relative shrink-0 overflow-hidden rounded-lg bg-zinc-100 ${className}`}>
      {url ? (
        <Image src={url} alt="" fill sizes="40px" className="object-cover" />
      ) : (
        <div className="flex h-full w-full items-center justify-center text-[9px] font-bold text-zinc-300">
          IMG
        </div>
      )}
    </div>
  );
}

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
      include: {
        items: {
          select: { quantity: true, product: { select: { imageUrl: true } } },
        },
      },
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
    <AdminPage maxWidth="xl">
      <PageHeader
        title="Manajemen Order"
        subtitle={`${total} order ditemukan${activeStatus !== "ALL" ? " dengan filter aktif" : ""}.`}
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            ← Dashboard
          </Button>
        }
      />

      {/* Type tabs — pill style natalo blue saat aktif */}
      <div className="-mx-4 mt-5 flex gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:mt-6 md:flex-wrap md:overflow-visible md:px-0">
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
                ? "bg-natalo-600 text-white shadow-[0_4px_12px_-2px_rgba(30,95,191,0.4)]"
                : "border border-zinc-200 bg-white text-zinc-600 hover:border-zinc-400"
            }`}
          >
            {tab.label}
          </Link>
        ))}
      </div>

      {/* Status tabs — dark zinc saat aktif (clear hierarchy vs type tabs) */}
      <div className="-mx-4 mt-3 flex gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:mt-4 md:flex-wrap md:overflow-visible md:px-0">
        {tabs.map((tab) => (
          <Link
            key={tab.key}
            href={buildUrl({ status: tab.key })}
            className={`inline-flex shrink-0 items-center gap-2 rounded-full px-4 py-2 text-sm font-bold transition ${
              activeStatus === tab.key
                ? "bg-zinc-950 text-white shadow-sm"
                : "border border-zinc-200 bg-white text-zinc-600 hover:border-zinc-400"
            }`}
          >
            {tab.label}
            <span
              className={`rounded-full px-2 py-0.5 text-xs font-black ${
                activeStatus === tab.key
                  ? "bg-white/20 text-white"
                  : "bg-zinc-100 text-zinc-600"
              }`}
            >
              {tab.count}
            </span>
          </Link>
        ))}
      </div>

      {/* Payment filter — smaller pills, secondary axis */}
      <div className="-mx-4 mt-3 flex items-center gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:mt-4 md:flex-wrap md:overflow-visible md:px-0">
        <span className="shrink-0 text-xs font-semibold text-zinc-500">
          Pembayaran:
        </span>
        {(["ALL", "WAITING", "UNPAID", "PENDING", "PAID", "FAILED", "EXPIRED"] as const).map(
          (p) => (
            <Link
              key={p}
              href={buildUrl({ pay: p })}
              className={`shrink-0 rounded-full px-3 py-1 text-xs font-bold transition ${
                activePay === p
                  ? "bg-zinc-950 text-white"
                  : "border border-zinc-200 bg-white text-zinc-600 hover:border-zinc-400"
              }`}
            >
              {p === "ALL" ? "Semua" : paymentStatusLabel(p)}
            </Link>
          ),
        )}
      </div>

      {/* Empty state */}
      {orders.length === 0 ? (
        <div className="mt-6 overflow-hidden rounded-2xl border border-zinc-200 bg-white">
          <EmptyState
            icon="📦"
            title="Tidak ada order"
            description="Coba ganti filter di atas untuk lihat order lain."
            size="full"
          />
        </div>
      ) : (
        <>
          {/* Mobile card list */}
          <div className="mt-5 space-y-3 md:hidden">
            {orders.map((order) => {
              const totalQty = order.items.reduce((s, i) => s + i.quantity, 0);
              const firstImg = order.items[0]?.product?.imageUrl ?? null;
              const cta = orderCtaLabel(order);
              return (
                <Link
                  key={order.id}
                  href={`/admin/orders/${order.id}`}
                  className="block rounded-2xl border border-zinc-200 bg-white p-4 transition active:scale-[0.99] hover:border-zinc-300 hover:shadow-sm"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex min-w-0 items-start gap-2.5">
                      <OrderThumb url={firstImg} className="h-9 w-9" />
                      <div className="min-w-0">
                        <p className="truncate font-black text-zinc-950">
                          {order.orderNumber}
                        </p>
                        <p className="mt-0.5 text-xs text-zinc-500">
                          {new Date(order.createdAt).toLocaleString("id-ID", {
                            day: "numeric",
                            month: "short",
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </p>
                      </div>
                    </div>
                    <span className="shrink-0 text-base font-black text-zinc-950">
                      {formatRupiah(order.total)}
                    </span>
                  </div>

                  <div className="mt-2.5 flex items-center justify-between gap-3 text-sm">
                    <div className="min-w-0">
                      <p className="truncate font-semibold text-zinc-800">
                        {order.customerName}
                      </p>
                      <p className="truncate text-xs text-zinc-500">
                        {order.customerPhone}
                      </p>
                    </div>
                    <span className="shrink-0 text-[11px] font-bold text-zinc-500">
                      {totalQty} item ·{" "}
                      {order.orderType === "SELF_PICKUP" ? "Pickup" : "Delivery"}
                    </span>
                  </div>

                  <div className="mt-3 flex flex-wrap gap-1.5">
                    <Badge variant={EXTRA_STATUS_VARIANT[order.status] ?? "neutral"}>
                      {orderStatusLabel(order.status)}
                    </Badge>
                    <Badge
                      variant={EXTRA_PAY_VARIANT[order.paymentStatus] ?? "neutral"}
                    >
                      {paymentStatusLabel(order.paymentStatus)}
                    </Badge>
                  </div>

                  <div className="mt-3 border-t border-zinc-100 pt-2.5">
                    <span
                      className={`inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-bold ${CTA_PILL_CLASSES[cta.variant]}`}
                    >
                      {cta.label} →
                    </span>
                  </div>
                </Link>
              );
            })}
          </div>

          {/* Desktop table */}
          <div className="mt-6 hidden overflow-hidden rounded-2xl border border-zinc-200 bg-white md:block">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-zinc-100 bg-zinc-50/50">
                    <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Order
                    </th>
                    <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Customer
                    </th>
                    <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Total
                    </th>
                    <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Pembayaran
                    </th>
                    <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Status
                    </th>
                    <th className="hidden px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500 lg:table-cell">
                      Tanggal
                    </th>
                    <th className="px-5 py-3.5" />
                  </tr>
                </thead>
                <tbody>
                  {orders.map((order) => {
                    const totalQty = order.items.reduce(
                      (s, i) => s + i.quantity,
                      0,
                    );
                    const initial =
                      order.customerName?.[0]?.toUpperCase() ?? "?";
                    const firstImg =
                      order.items[0]?.product?.imageUrl ?? null;
                    const cta = orderCtaLabel(order);
                    return (
                      <tr
                        key={order.id}
                        className="group border-b border-zinc-100 last:border-0 transition hover:bg-natalo-50/40"
                      >
                        <td className="px-5 py-4">
                          <div className="flex items-start gap-3">
                            <OrderThumb url={firstImg} />
                            <div className="min-w-0">
                              <p className="font-black text-zinc-950">
                                {order.orderNumber}
                              </p>
                              <p className="mt-0.5 text-xs text-zinc-500">
                                {totalQty} item
                              </p>
                              <p className="mt-1 text-[11px] font-bold text-zinc-500">
                                {order.orderType === "SELF_PICKUP"
                                  ? "Ambil Sendiri di Toko"
                                  : "Delivery"}
                              </p>
                            </div>
                          </div>
                        </td>
                        <td className="px-5 py-4">
                          <div className="flex items-center gap-2.5">
                            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-natalo-50 text-xs font-black text-natalo-700">
                              {initial}
                            </div>
                            <div className="min-w-0">
                              <p className="truncate font-semibold text-zinc-950">
                                {order.customerName}
                              </p>
                              <p className="truncate text-xs text-zinc-500">
                                {order.customerPhone}
                              </p>
                            </div>
                          </div>
                        </td>
                        <td className="px-5 py-4">
                          <span className="font-black text-zinc-950">
                            {formatRupiah(order.total)}
                          </span>
                        </td>
                        <td className="px-5 py-4">
                          <Badge
                            variant={
                              EXTRA_PAY_VARIANT[order.paymentStatus] ?? "neutral"
                            }
                            size="md"
                          >
                            {paymentStatusLabel(order.paymentStatus)}
                          </Badge>
                        </td>
                        <td className="px-5 py-4">
                          <Badge
                            variant={
                              EXTRA_STATUS_VARIANT[order.status] ?? "neutral"
                            }
                            size="md"
                          >
                            {orderStatusLabel(order.status)}
                          </Badge>
                        </td>
                        <td className="hidden px-5 py-4 text-xs text-zinc-500 lg:table-cell">
                          {new Date(order.createdAt).toLocaleDateString("id-ID", {
                            day: "numeric",
                            month: "short",
                            year: "numeric",
                          })}
                        </td>
                        <td className="px-5 py-4">
                          <Button
                            href={`/admin/orders/${order.id}`}
                            variant={cta.variant}
                            size="sm"
                          >
                            {cta.label}
                          </Button>
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
            Halaman <span className="font-black text-zinc-950">{page}</span> dari{" "}
            <span className="font-black text-zinc-950">{totalPages}</span>
          </p>
          <div className="flex gap-2">
            {page > 1 && (
              <Button
                href={buildUrl({ page: String(page - 1) })}
                variant="secondary"
                size="sm"
              >
                ← Sebelumnya
              </Button>
            )}
            {page < totalPages && (
              <Button
                href={buildUrl({ page: String(page + 1) })}
                variant="primary"
                size="sm"
              >
                Berikutnya →
              </Button>
            )}
          </div>
        </div>
      )}
    </AdminPage>
  );
}
