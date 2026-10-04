import { AdminDisclosure } from "@/components/admin/ui/AdminDisclosure";
import Link from "next/link";
import Image from "next/image";
import { formatRupiah } from "@/lib/format";
import {
  PageHeader,
  StatCard,
  EmptyState,
  Badge,
  Button,
  AdminPage,
  Pagination,
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
    <div
      className={`relative shrink-0 overflow-hidden rounded-lg bg-zinc-100 ${className}`}
    >
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

export type OrdersViewProps = {
  workflowCounts: {
    verification: number;
    packing: number;
    pickup: number;
    total: number;
  };
  pendingProofReview?: boolean;
  todayOnly?: boolean;
  orders: Array<{
    id: string;
    orderNumber: string;
    customerName: string;
    customerPhone: string | null;
    createdAt: Date;
    total: number;
    status: string;
    paymentStatus: string;
    orderType: string;
    cancellationRequestStatus: string | null;
    items: Array<{
      quantity: number;
      product: { imageUrl: string | null } | null;
    }>;
  }>;
  total: number;
  search: string;
  page: number;
  totalPages: number;
  tabs: Array<{ key: string; label: string; count: number }>;
  activeStatus: string;
  activePay: string;
  activeType: string;
  buildUrl: (overrides: Record<string, string>) => string;
};
export function OrdersView({
  workflowCounts,
  orders,
  total,
  search,
  page,
  totalPages,
  tabs,
  activeStatus,
  activePay,
  activeType,
  buildUrl,
  pendingProofReview = false,
  todayOnly = false,
}: OrdersViewProps) {
  return (
    <AdminPage
      maxWidth="xl"
      className="admin-operational-page admin-refined-page"
    >
      <PageHeader
        eyebrow="Operasional"
        title="Pesanan"
        subtitle={
          search
            ? `${total} pesanan cocok dengan "${search}".`
            : `${total} pesanan ditemukan${
                activeStatus !== "ALL" ? " dengan filter aktif" : ""
              }.`
        }
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            Kembali ke ringkasan
          </Button>
        }
      />
      <section
        className="admin-workflow-metrics"
        aria-label="Ringkasan semua pesanan"
      >
        <StatCard
          label="Perlu verifikasi"
          value={workflowCounts.verification}
          helper="Bukti pembayaran masuk"
          href="/admin/orders?proof=PENDING_REVIEW"
        />
        <StatCard
          label="Perlu dikemas"
          value={workflowCounts.packing}
          helper="Sudah lunas"
          href="/admin/orders?status=NEED_PACKING"
          variant="accent"
        />
        <StatCard
          label="Siap diambil"
          value={workflowCounts.pickup}
          helper="Pengambilan di toko"
          href="/admin/orders?type=SELF_PICKUP&status=READY_FOR_PICKUP&pay=PAID"
        />
        <StatCard
          label="Semua pesanan"
          value={workflowCounts.total}
          helper="Seluruh status"
          href="/admin/orders"
        />
      </section>
      <section className="admin-list-workspace" aria-label="Daftar pesanan">
        {todayOnly && (
          <div className="mt-5 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-blue-100 bg-blue-50 px-4 py-3 text-sm text-blue-900">
            <p>
              {activePay === "PAID"
                ? "Pesanan lunas yang masuk hari ini (WIB), selain pesanan batal dan refund."
                : "Pesanan yang masuk hari ini (WIB)."}
            </p>
            <Link
              href={buildUrl({ date: "" })}
              className="inline-flex min-h-11 items-center font-semibold underline"
            >
              Hapus filter tanggal
            </Link>
          </div>
        )}
        {pendingProofReview && (
          <div className="mt-5 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-blue-100 bg-blue-50 px-4 py-3 text-sm text-blue-900">
            <p>Menampilkan bukti pembayaran yang menunggu verifikasi.</p>
            <Link
              href={buildUrl({ proof: "" })}
              className="inline-flex min-h-11 items-center font-semibold underline"
            >
              Hapus filter
            </Link>
          </div>
        )}
        {/* Status tabs — filter UTAMA (alur kerja harian), satu aksen natalo
          blue konsisten. Dulu bersaing dgn Type (biru) + Payment (hitam)
          jadi 3 warna aktif berbeda; kini SATU aksen di seluruh halaman. */}
        <div className="admin-filter-tabs" aria-label="Status pesanan">
          {tabs.map((tab) => (
            <Link
              key={tab.key}
              href={buildUrl({ status: tab.key })}
              aria-current={activeStatus === tab.key ? "page" : undefined}
              className={`inline-flex shrink-0 items-center gap-2 rounded-full px-4 py-2 text-sm font-bold transition ${
                activeStatus === tab.key
                  ? "bg-natalo-600 text-white shadow-[0_4px_12px_-2px_rgba(30,95,191,0.4)]"
                  : "border border-zinc-200 bg-white text-zinc-600 hover:border-zinc-400"
              }`}
            >
              {tab.label}
              <span
                className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
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

        {/* Type + Payment — filter SEKUNDER, digabung jadi 1 baris ringan
          (dulu 2 baris terpisah dgn bobot visual sama besar dgn Status).
          Type jadi segmented-control kecil, Payment jadi pill tenang. */}
        <div className="mt-4">
          <AdminDisclosure
            title={`Pengiriman & pembayaran${
              activeType !== "ALL" || activePay !== "ALL"
                ? " · Filter aktif"
                : ""
            }`}
          >
            <div className="admin-filter-secondary">
              <div className="inline-flex shrink-0 gap-0.5 rounded-full border border-zinc-200 bg-white p-1">
                {[
                  { key: "ALL", label: "Semua" },
                  { key: "DELIVERY", label: "Delivery" },
                  { key: "SELF_PICKUP", label: "Self Pick Up" },
                ].map((tab) => (
                  <Link
                    key={tab.key}
                    href={buildUrl({ type: tab.key })}
                    aria-current={activeType === tab.key ? "page" : undefined}
                    className={`rounded-full px-3 py-1 text-xs font-bold transition ${
                      activeType === tab.key
                        ? "bg-zinc-100 text-zinc-900"
                        : "text-zinc-500 hover:text-zinc-700"
                    }`}
                  >
                    {tab.label}
                  </Link>
                ))}
              </div>

              <span className="hidden h-4 w-px shrink-0 bg-zinc-200 md:block" />

              <div className="flex flex-wrap items-center gap-1.5 overflow-x-auto">
                {(
                  [
                    "ALL",
                    "WAITING",
                    "UNPAID",
                    "PENDING",
                    "PAID",
                    "FAILED",
                    "EXPIRED",
                  ] as const
                ).map((p) => (
                  <Link
                    key={p}
                    href={buildUrl({ pay: p })}
                    aria-current={activePay === p ? "page" : undefined}
                    className={`shrink-0 rounded-full px-2.5 py-1 text-xs font-bold transition ${
                      activePay === p
                        ? "bg-natalo-50 text-natalo-700"
                        : "text-zinc-500 hover:bg-zinc-50 hover:text-zinc-700"
                    }`}
                  >
                    {p === "ALL" ? "Semua pembayaran" : paymentStatusLabel(p)}
                  </Link>
                ))}
              </div>
            </div>
          </AdminDisclosure>
        </div>

        {/* Kotak cari — satu input untuk tiga hal sekaligus (nomor pesanan,
          nama, nomor HP) karena saat customer bertanya, admin tidak selalu
          punya nomor pesanannya. Filter aktif ikut terbawa lewat hidden
          input supaya pencarian menyempitkan, bukan menyetel ulang. */}
        <form className="admin-searchbar" method="GET" action="/admin/orders">
          {todayOnly && <input type="hidden" name="date" value="TODAY" />}
          {pendingProofReview && (
            <input type="hidden" name="proof" value="PENDING_REVIEW" />
          )}
          {activeStatus !== "ALL" && (
            <input type="hidden" name="status" value={activeStatus} />
          )}
          {activePay !== "ALL" && (
            <input type="hidden" name="pay" value={activePay} />
          )}
          {activeType !== "ALL" && (
            <input type="hidden" name="type" value={activeType} />
          )}
          <input
            type="search"
            name="q"
            defaultValue={search}
            aria-label="Cari nomor pesanan, nama pembeli, atau nomor HP"
            placeholder="Cari nomor pesanan, nama, atau nomor HP"
            className="min-w-0 flex-1 rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm outline-none focus:border-natalo-600"
          />
          <Button type="submit">Cari</Button>
          {search && (
            <Button href={buildUrl({ q: "" })} variant="secondary">
              Reset
            </Button>
          )}
        </form>

        {/* Empty state */}
        {orders.length === 0 ? (
          <div className="mt-6 overflow-hidden rounded-2xl border border-zinc-200 bg-white">
            <EmptyState
              icon={search ? "🔍" : "📦"}
              title={
                search
                  ? `Tidak ada pesanan cocok "${search}"`
                  : "Tidak ada pesanan"
              }
              description={
                search
                  ? "Coba kata kunci lain, atau reset pencarian. Filter status di atas juga ikut membatasi hasil."
                  : "Coba ganti filter di atas untuk lihat pesanan lain."
              }
              size="full"
            />
          </div>
        ) : (
          <>
            {/* Mobile card list */}
            <div className="mt-5 space-y-3 xl:hidden">
              {orders.map((order) => {
                const totalQty = order.items.reduce(
                  (s, i) => s + i.quantity,
                  0
                );
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
                          <p className="truncate font-semibold text-zinc-950">
                            {order.orderNumber}
                          </p>
                          <p className="mt-0.5 text-xs text-zinc-500">
                            {new Date(order.createdAt).toLocaleString("id-ID", {
                              day: "numeric",
                              month: "short",
                              hour: "2-digit",
                              minute: "2-digit",
                              timeZone: "Asia/Jakarta",
                            })}
                          </p>
                        </div>
                      </div>
                      <span className="shrink-0 text-base font-semibold text-zinc-950">
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
                      <span className="shrink-0 text-xs font-bold text-zinc-500">
                        {totalQty} item ·{" "}
                        {order.orderType === "SELF_PICKUP"
                          ? "Pickup"
                          : "Delivery"}
                      </span>
                    </div>

                    <div className="mt-3 flex flex-wrap gap-1.5">
                      <Badge
                        variant={
                          EXTRA_STATUS_VARIANT[order.status] ?? "neutral"
                        }
                      >
                        {orderStatusLabel(order.status)}
                      </Badge>
                      <Badge
                        variant={
                          EXTRA_PAY_VARIANT[order.paymentStatus] ?? "neutral"
                        }
                      >
                        {paymentStatusLabel(order.paymentStatus)}
                      </Badge>
                    </div>

                    <div className="mt-3 border-t border-zinc-100 pt-2.5">
                      <span
                        className={`inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-bold ${
                          CTA_PILL_CLASSES[cta.variant]
                        }`}
                      >
                        {cta.label} →
                      </span>
                    </div>
                  </Link>
                );
              })}
            </div>

            {/* Desktop table */}
            <div className="mt-6 hidden overflow-hidden rounded-2xl border border-zinc-200 bg-white xl:block">
              <div className="overflow-x-auto">
                <table className="admin-data-table w-full text-sm">
                  <thead>
                    <tr className="border-b border-zinc-100 bg-zinc-50/50">
                      <th className="px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500">
                        Pesanan
                      </th>
                      <th className="px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500">
                        Pelanggan
                      </th>
                      <th className="px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500">
                        Total
                      </th>
                      <th className="px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500">
                        Pembayaran
                      </th>
                      <th className="px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500">
                        Status
                      </th>
                      <th className="hidden px-5 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-zinc-500 lg:table-cell">
                        Tanggal
                      </th>
                      <th className="px-5 py-3.5">
                        <span className="sr-only">Tindakan</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {orders.map((order) => {
                      const totalQty = order.items.reduce(
                        (s, i) => s + i.quantity,
                        0
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
                                <p className="font-semibold text-zinc-950">
                                  {order.orderNumber}
                                </p>
                                <p className="mt-0.5 text-xs text-zinc-500">
                                  {totalQty} item
                                </p>
                                <p className="mt-1 text-xs font-bold text-zinc-500">
                                  {order.orderType === "SELF_PICKUP"
                                    ? "Ambil Sendiri di Toko"
                                    : "Delivery"}
                                </p>
                              </div>
                            </div>
                          </td>
                          <td className="px-5 py-4">
                            <div className="flex items-center gap-2.5">
                              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-natalo-50 text-xs font-semibold text-natalo-700">
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
                          <td className="whitespace-nowrap px-5 py-4">
                            <span className="font-semibold tabular-nums text-zinc-950">
                              {formatRupiah(order.total)}
                            </span>
                          </td>
                          <td className="px-5 py-4">
                            <Badge
                              variant={
                                EXTRA_PAY_VARIANT[order.paymentStatus] ??
                                "neutral"
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
                            {new Date(order.createdAt).toLocaleDateString(
                              "id-ID",
                              {
                                day: "numeric",
                                month: "short",
                                year: "numeric",
                                timeZone: "Asia/Jakarta",
                              }
                            )}
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
        <Pagination
          currentPage={page}
          totalPages={totalPages}
          hrefFor={(target) => buildUrl({ page: String(target) })}
          summary={`${total} pesanan`}
        />
      </section>
    </AdminPage>
  );
}
