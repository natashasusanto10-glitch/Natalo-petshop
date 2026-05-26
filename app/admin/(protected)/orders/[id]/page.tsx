import Link from "next/link";
import Image from "next/image";
import { notFound } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { SELF_PICKUP_STORE } from "@/lib/self-pickup";
import {
  markAsCancelled,
  createShipment,
  issueRefundToWallet,
  markAsDelivered,
  markAsPaid,
  markAsPickedUp,
  markAsProcessing,
  markAsReadyForPickup,
  markAsShipped,
  markItemPartiallyOutOfStock,
  approveCancellationRequest,
  rejectCancellationRequest,
} from "./actions";
import ItemOutOfStockButton from "./ItemOutOfStockButton";
import RefundFormClient from "./RefundFormClient";
import CancelOrderButton from "./CancelOrderButton";
import CancellationRequestBanner from "./CancellationRequestBanner";
import ShippingForm from "./ShippingForm";

const STATUS_LABELS: Record<string, string> = {
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
  UNPAID: "Belum bayar",
  PENDING: "Menunggu verifikasi",
  PAID: "Lunas",
  FAILED: "Gagal",
  EXPIRED: "Kedaluwarsa",
  REFUNDED: "Refund",
};

const PAY_COLORS: Record<string, string> = {
  UNPAID: "bg-red-100 text-red-700",
  PENDING: "bg-amber-100 text-amber-700",
  PAID: "bg-green-100 text-green-700",
  FAILED: "bg-red-100 text-red-700",
  EXPIRED: "bg-zinc-100 text-zinc-600",
  REFUNDED: "bg-zinc-100 text-zinc-600",
};

export default async function AdminOrderDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const markAsPaidAction = markAsPaid.bind(null, id);
  const markAsProcessingAction = markAsProcessing.bind(null, id);
  const markAsReadyForPickupAction = markAsReadyForPickup.bind(null, id);
  const markAsPickedUpAction = markAsPickedUp.bind(null, id);
  const markAsShippedAction = markAsShipped.bind(null, id);
  const markAsDeliveredAction = markAsDelivered.bind(null, id);
  const markAsCancelledAction = markAsCancelled.bind(null, id);
  const approveCancellationAction = approveCancellationRequest.bind(null, id);
  const rejectCancellationAction = rejectCancellationRequest.bind(null, id);
  const createShipmentAction = createShipment.bind(null, id);

  const issueRefundToWalletAction = issueRefundToWallet.bind(null, id);
  const markItemOutOfStockAction = markItemPartiallyOutOfStock.bind(null, id);

  // ── Data Fetch ──────────────────────────────────────────────
  const order = await prisma.order.findUnique({
    where: { id },
    include: {
      items: true,
      refundCases: {
        orderBy: { createdAt: "desc" },
      },
      // Granular voucher tracking — per-voucher discount amount + tipe.
      // Dipakai untuk tampilan "Voucher X (-Rp 2.500)" inline di admin
      // summary. Order punya 4 slot voucher (productVoucher, shipping,
      // loyalty, manualVoucher), VoucherUsage track amount per voucher
      // per order (1:N relation).
      voucherUsages: {
        include: {
          voucher: {
            select: {
              code: true,
              name: true,
              type: true,
              kind: true,
              discountScope: true,
            },
          },
        },
        orderBy: { usedAt: "asc" },
      },
    },
  });

  if (!order) return notFound();
  const totalRefunded = order.refundCases
    .filter((rc) => rc.status === "CREDITED")
    .reduce((sum, rc) => sum + rc.amount, 0);
  const isSelfPickup = order.orderType === "SELF_PICKUP";

  // Sanitize phone — strip non-digit, lalu normalisasi prefix 0/62/+62.
  // Kalau hasilnya tidak masuk akal (kurang dari 9 digit), hide tombol WA.
  const phoneDigits = (order.customerPhone ?? "").replace(/\D/g, "");
  const waNumber = phoneDigits.startsWith("0")
    ? `62${phoneDigits.slice(1)}`
    : phoneDigits.startsWith("62")
    ? phoneDigits
    : phoneDigits.startsWith("8")
    ? `62${phoneDigits}`
    : phoneDigits;
  const isPhoneValid = waNumber.length >= 10 && waNumber.startsWith("62");

  const waText = encodeURIComponent(
    `Halo ${order.customerName}, kami dari Natalo Petshop & Aquarium. ` +
      `Order ${order.orderNumber} sudah kami terima dengan total ${formatRupiah(order.total)}.`
  );

  const isDone = order.status === "DELIVERED" || order.status === "CANCELLED" || order.status === "REFUNDED";

  return (
    <div className="mx-auto max-w-5xl px-4 py-5 md:py-10">
      <Link
        href="/admin/orders"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke daftar order
      </Link>

      <div className="mt-4 flex flex-wrap items-start justify-between gap-3 md:mt-6 md:gap-4">
        <div className="min-w-0">
          <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">Detail Order</h1>
          <p className="mt-1 truncate text-zinc-500">{order.orderNumber}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2 md:gap-3">
          <span
            className={`rounded-full px-3 py-1.5 text-xs font-bold md:px-4 md:py-2 md:text-sm ${
              PAY_COLORS[order.paymentStatus] ?? "bg-zinc-100 text-zinc-600"
            }`}
          >
            {PAY_LABELS[order.paymentStatus] ?? order.paymentStatus}
          </span>
          <span
            className={`rounded-full px-3 py-1.5 text-xs font-bold md:px-4 md:py-2 md:text-sm ${
              STATUS_COLORS[order.status] ?? "bg-zinc-100 text-zinc-600"
            }`}
          >
            {STATUS_LABELS[order.status] ?? order.status}
          </span>
          <Link
            href={`/admin/orders/${id}/print`}
            target="_blank"
            className="flex items-center gap-2 rounded-full border border-zinc-200 px-3 py-1.5 text-xs font-bold text-zinc-700 transition hover:border-zinc-400 hover:text-zinc-950 md:px-4 md:py-2 md:text-sm"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-4 w-4">
              <path d="M6 9V2h12v7" />
              <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2" />
              <rect x="6" y="14" width="12" height="8" />
            </svg>
            Cetak Label
          </Link>
        </div>
      </div>

      {/* Cancellation request banner — muncul kalau customer sudah submit
          request batal (paymentStatus=PAID flow). Untuk status APPROVED/
          REJECTED tampil sebagai history view (audit trail). PENDING
          tampil actionable dengan tombol Setujui/Tolak. */}
      {order.cancellationRequestStatus && (
        <CancellationRequestBanner
          status={order.cancellationRequestStatus as "PENDING" | "APPROVED" | "REJECTED"}
          reason={order.cancellationReason}
          requestedAt={order.cancellationRequestedAt?.toISOString() ?? null}
          respondedAt={order.cancellationRespondedAt?.toISOString() ?? null}
          rejectReason={order.cancellationRejectReason}
          approveAction={approveCancellationAction}
          rejectAction={rejectCancellationAction}
        />
      )}

      <div className="mt-5 grid gap-4 md:mt-8 md:gap-6 lg:grid-cols-[1fr_340px]">
        {/* ── Produk ── */}
        <section className="rounded-2xl border border-zinc-200 p-4 md:rounded-3xl md:p-5">
          <h2 className="font-bold text-zinc-950">Produk dibeli</h2>

          <div className="mt-4 space-y-3">
            {order.items.map((item) => (
              <div
                key={item.id}
                className="rounded-2xl bg-zinc-50 p-4 text-sm"
              >
                <div className="flex justify-between gap-4">
                  <div>
                    <p className="font-semibold text-zinc-950">{item.name}</p>
                    <p className="mt-1 text-zinc-500">
                      {item.quantity} × {formatRupiah(item.price)}
                    </p>
                  </div>
                  <p className="font-bold text-zinc-950">
                    {formatRupiah(item.price * item.quantity)}
                  </p>
                </div>
                {/* Quick action: tandai item kosong saat packing → auto-
                    refund. Cuma muncul kalau order belum FINAL (DELIVERED
                    /CANCELLED). Reuse RefundFormClient untuk kasus
                    kompleks (full form di section bawah). */}
                {order.status !== "CANCELLED" &&
                  order.status !== "REFUNDED" && (
                    <div className="mt-2 flex justify-end">
                      <ItemOutOfStockButton
                        itemId={item.id}
                        itemName={item.name}
                        itemPrice={item.price}
                        itemQuantity={item.quantity}
                        orderSubtotal={order.subtotal ?? 0}
                        orderProductDiscount={order.productDiscount ?? 0}
                        action={markItemOutOfStockAction}
                      />
                    </div>
                  )}
              </div>
            ))}
          </div>

          <div className="mt-6 space-y-2 border-t border-zinc-100 pt-4 text-sm">
            {/* Subtotal & Ongkir — base nominal sebelum diskon */}
            <div className="flex justify-between text-zinc-600">
              <span>Subtotal</span>
              <span>{formatRupiah(order.subtotal)}</span>
            </div>
            <div className="flex justify-between text-zinc-600">
              <span>Ongkir</span>
              <span>{formatRupiah(order.shippingCost)}</span>
            </div>

            {/* Diskon granular — split antara produk vs ongkir vs legacy
                supaya admin tahu darimana datangnya diskon. Schema sudah
                track per-kategori, tinggal display. */}
            {order.productDiscount > 0 && (
              <div className="flex justify-between text-zinc-600">
                <span>
                  Diskon Produk
                  {(order.productVoucherCode || order.voucherCode) && (
                    <span className="ml-1 text-xs text-zinc-400">
                      ({order.productVoucherCode || order.voucherCode})
                    </span>
                  )}
                </span>
                <span className="text-red-600">
                  -{formatRupiah(order.productDiscount)}
                </span>
              </div>
            )}
            {order.shippingDiscount > 0 && (
              <div className="flex justify-between text-zinc-600">
                <span>
                  Diskon Ongkir
                  {order.shippingVoucherCode && (
                    <span className="ml-1 text-xs text-zinc-400">
                      ({order.shippingVoucherCode})
                    </span>
                  )}
                </span>
                <span className="text-red-600">
                  -{formatRupiah(order.shippingDiscount)}
                </span>
              </div>
            )}
            {/* Fallback: kalau ada order.discount tapi belum ke-split ke
                product/shipping (legacy order pre-refactor), tampilkan
                aggregate supaya admin tetap lihat. */}
            {order.discount > 0 &&
              order.discount > order.productDiscount + order.shippingDiscount && (
                <div className="flex justify-between text-zinc-600">
                  <span>Diskon Lainnya</span>
                  <span className="text-red-600">
                    -
                    {formatRupiah(
                      order.discount -
                        order.productDiscount -
                        order.shippingDiscount,
                    )}
                  </span>
                </div>
              )}

            {/* Saldo Refund — line baru. Saat user pakai saldo refund
                sebagai metode bayar (full/partial), tampilkan supaya admin
                tau dari mana selisih ke Total. Sebelumnya invisible →
                admin bingung "kok Total 0 padahal subtotal 25rb". */}
            {order.refundBalanceUsed > 0 && (
              <div className="flex justify-between text-blue-700">
                <span>🎁 Bayar via Saldo Refund</span>
                <span>-{formatRupiah(order.refundBalanceUsed)}</span>
              </div>
            )}

            {/* Total bayar tunai — prominent. Q4: tegasin supaya admin
                langsung paham ini nominal yang user beneran bayar via
                transfer/Midtrans/dst. Kalau 0, admin tahu order full
                ke-cover saldo refund + voucher, gak ada yang nunggu. */}
            <div className="flex justify-between border-t border-zinc-200 pt-3 mt-2 text-lg font-black text-zinc-950">
              <span>Total Bayar Tunai</span>
              <span
                className={
                  order.total === 0 ? "text-emerald-600" : "text-zinc-950"
                }
              >
                {formatRupiah(order.total)}
              </span>
            </div>
            {order.total === 0 && order.refundBalanceUsed > 0 && (
              <p className="text-xs font-semibold text-emerald-700 -mt-1">
                ✓ Order ke-cover full oleh saldo + voucher — tidak ada
                yang perlu di-transfer
              </p>
            )}

            {/* Already-refunded — beda dari refundBalanceUsed (Q3 keep
                terpisah). Ini nominal yang DI-credit balik ke user dari
                order ini (mis. partial refund OOS), bukan saldo yang
                dipakai bayar order. */}
            {totalRefunded > 0 && (
              <div className="flex justify-between text-amber-700 border-t border-amber-200 pt-2 mt-2">
                <span>↩ Sudah di-refund ke user</span>
                <span>-{formatRupiah(totalRefunded)}</span>
              </div>
            )}
          </div>

          {/* ── Saldo Refund Section ──
              Form kredit baru disembunyikan kalau order udah final
              (DELIVERED/CANCELLED/REFUNDED) — match dengan guard di
              server action issueRefundToWallet. Kalau CANCELLED, saldo
              udah otomatis di-reverse via markAsCancelled — refund manual
              di sini akan double-refund. History tetap dirender untuk
              audit trail (kalau ada). */}
          {!isDone ? (
            <details className="mt-6 rounded-2xl border border-zinc-200 bg-zinc-50/50 p-3">
              {/* Collapsible (default closed) — 90% kasus refund cukup
                  pakai tombol "Tandai kosong" per-item di card produk.
                  Section ini hanya untuk kasus jarang: return, partial
                  cancel, atau override custom nominal. ORDER_CANCELLED
                  dihilangkan dari dropdown — pembatalan order otomatis
                  trigger auto-refund via tombol "Batalkan Order". */}
              <summary className="cursor-pointer text-sm font-semibold text-zinc-700 hover:text-zinc-900">
                Refund untuk kasus lain
                <span className="ml-1 font-normal text-zinc-500">
                  (return, batal sebagian, custom nominal)
                </span>
              </summary>
              <p className="mt-3 text-xs text-zinc-600">
                Kredit Saldo Refund user untuk kasus yang tidak ke-cover
                tombol &quot;Tandai kosong&quot; per-item. Saldo masuk
                instant dan bisa user pakai di checkout berikutnya.
              </p>
              <RefundFormClient
                items={order.items.map((it) => ({
                  id: it.id,
                  name: it.name,
                  quantity: it.quantity,
                  price: it.price,
                }))}
                action={issueRefundToWalletAction}
                orderSubtotal={order.subtotal ?? 0}
                orderProductDiscount={order.productDiscount ?? 0}
                orderShippingFee={order.shippingCost ?? 0}
                orderShippingDiscount={order.shippingDiscount ?? 0}
              />

              {/* History refund per order ini */}
              {order.refundCases.length > 0 && (
                <div className="mt-4 border-t border-blue-200 pt-3">
                  <p className="text-xs font-semibold text-blue-900">
                    Riwayat refund order ini ({order.refundCases.length})
                  </p>
                  <ul className="mt-2 space-y-1.5 text-xs">
                    {order.refundCases.map((rc) => (
                      <li
                        key={rc.id}
                        className="flex items-center justify-between rounded bg-white px-3 py-2"
                      >
                        <span>
                          <span
                            className={`mr-2 inline-block rounded px-1.5 py-0.5 text-[10px] font-bold ${
                              rc.status === "CREDITED"
                                ? "bg-emerald-100 text-emerald-700"
                                : rc.status === "REJECTED"
                                  ? "bg-red-100 text-red-700"
                                  : "bg-amber-100 text-amber-700"
                            }`}
                          >
                            {rc.status}
                          </span>
                          {rc.reason.replace(/_/g, " ").toLowerCase()}
                        </span>
                        <span className="font-semibold text-zinc-900">
                          {formatRupiah(rc.amount)}
                        </span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </details>
          ) : (
            order.refundCases.length > 0 && (
              <div className="mt-6 rounded-2xl border border-zinc-200 bg-zinc-50 p-4">
                <p className="text-xs font-semibold text-zinc-700">
                  Riwayat refund order ini ({order.refundCases.length})
                </p>
                <p className="mt-1 text-[11px] text-zinc-500">
                  Order sudah {order.status === "CANCELLED" ? "dibatalkan" : order.status === "REFUNDED" ? "di-refund penuh" : "selesai"} —
                  refund baru tidak bisa dilakukan dari sini.
                </p>
                <ul className="mt-3 space-y-1.5 text-xs">
                  {order.refundCases.map((rc) => (
                    <li
                      key={rc.id}
                      className="flex items-center justify-between rounded bg-white px-3 py-2"
                    >
                      <span>
                        <span
                          className={`mr-2 inline-block rounded px-1.5 py-0.5 text-[10px] font-bold ${
                            rc.status === "CREDITED"
                              ? "bg-emerald-100 text-emerald-700"
                              : rc.status === "REJECTED"
                                ? "bg-red-100 text-red-700"
                                : "bg-amber-100 text-amber-700"
                          }`}
                        >
                          {rc.status}
                        </span>
                        {rc.reason.replace(/_/g, " ").toLowerCase()}
                      </span>
                      <span className="font-semibold text-zinc-900">
                        {formatRupiah(rc.amount)}
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            )
          )}
        </section>

        {/* ── Sidebar ── */}
        <aside className="space-y-5">
          {/* Customer */}
          <section className="rounded-2xl border border-zinc-200 p-4 md:rounded-3xl md:p-5">
            <h2 className="font-bold text-zinc-950">Customer</h2>
            <div className="mt-4 space-y-2 text-sm text-zinc-700">
              <p>
                <span className="font-semibold">Nama:</span> {order.customerName}
              </p>
              <p>
                <span className="font-semibold">WhatsApp:</span>{" "}
                {order.customerPhone || <span className="text-zinc-400 italic">tidak diisi</span>}
              </p>
              {order.customerEmail && (
                <p>
                  <span className="font-semibold">Email:</span> {order.customerEmail}
                </p>
              )}
            </div>
            {isPhoneValid ? (
              <a
                href={`https://wa.me/${waNumber}?text=${waText}`}
                target="_blank"
                rel="noreferrer"
                className="mt-5 inline-flex w-full justify-center rounded-full bg-green-600 px-5 py-3 text-sm font-bold text-white hover:bg-green-700"
              >
                Hubungi via WhatsApp
              </a>
            ) : (
              <p className="mt-5 rounded-full border border-dashed border-zinc-200 px-5 py-3 text-center text-xs font-semibold text-zinc-400">
                Nomor WhatsApp tidak valid
              </p>
            )}
          </section>

          {isSelfPickup && (
            <section className="rounded-3xl border border-green-200 bg-green-50 p-5">
              <h2 className="font-bold text-zinc-950">Metode Pengambilan</h2>
              <div className="mt-4 space-y-2 text-sm text-zinc-700">
                <p>
                  <span className="font-semibold">Metode:</span> Ambil Sendiri di Toko
                </p>
                <p>
                  <span className="font-semibold">Lokasi:</span>{" "}
                  {order.pickupStoreName ?? SELF_PICKUP_STORE.name}
                </p>
                <p>{order.pickupStoreAddress ?? SELF_PICKUP_STORE.address}</p>
                <p>
                  <span className="font-semibold">Jam Ambil:</span>{" "}
                  {order.pickupHours ?? SELF_PICKUP_STORE.hours}
                </p>
                <p>
                  <span className="font-semibold">Status pickup:</span>{" "}
                  {order.pickupStatus ?? "-"}
                </p>
                {order.pickupCode && (
                  <p>
                    <span className="font-semibold">Kode pickup:</span>{" "}
                    <span className="font-mono font-black">{order.pickupCode}</span>
                  </p>
                )}
              </div>
            </section>
          )}

          {/* Pengiriman */}
          <section className={`rounded-3xl border border-zinc-200 p-5 ${isSelfPickup ? "hidden" : ""}`}>
            <h2 className="font-bold text-zinc-950">Pengiriman</h2>
            <div className="mt-4 space-y-2 text-sm text-zinc-700">
              <p>
                <span className="font-semibold">Alamat:</span> {order.shippingAddress}
              </p>
              {order.shippingCity && (
                <p>
                  <span className="font-semibold">Kota:</span> {order.shippingCity}
                </p>
              )}
              {order.shippingPostalCode && (
                <p>
                  <span className="font-semibold">Kode pos:</span> {order.shippingPostalCode}
                </p>
              )}
              {order.courierCode && (
                <p>
                  <span className="font-semibold">Kurir:</span> {order.courierCode}{" "}
                  {order.courierService}
                </p>
              )}
              {order.shippingLatitude !== null && order.shippingLongitude !== null && (
                <p>
                  <span className="font-semibold">Titik tujuan:</span>{" "}
                  {order.shippingLatitude}, {order.shippingLongitude}
                </p>
              )}
              <p>
                <span className="font-semibold">No. Resi:</span>{" "}
                {order.trackingNumber ? (
                  <span className="font-mono">{order.trackingNumber}</span>
                ) : (
                  <span className="text-zinc-400">-</span>
                )}
              </p>
              {/* Biteship section — tampil HANYA kalau ada biteshipOrderId
                  (artinya beneran sukses di-book via Biteship). Untuk order
                  yang biteshipError-only (mis. "Key has not been activated")
                  hide karena bukan info actionable untuk admin — Biteship
                  sengaja di-skip saat launch fase awal, admin book manual
                  via platform kurir + input resi via form di atas. */}
              {order.biteshipOrderId ? (
                <>
                  <p>
                    <span className="font-semibold">Biteship ID:</span>{" "}
                    <span className="font-mono">{order.biteshipOrderId}</span>
                  </p>
                  {order.shipmentStatus && (
                    <p>
                      <span className="font-semibold">Status shipment:</span>{" "}
                      {order.shipmentStatus}
                    </p>
                  )}
                  {order.biteshipTrackingUrl && (
                    <a
                      href={order.biteshipTrackingUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex text-sm font-bold text-natalo-700 hover:underline"
                    >
                      Lacak via Biteship →
                    </a>
                  )}
                  {order.biteshipError && (
                    <p className="rounded-xl bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">
                      Biteship: {order.biteshipError}
                    </p>
                  )}
                </>
              ) : (
                <p className="rounded-xl bg-zinc-50 px-3 py-2 text-xs font-semibold text-zinc-600">
                  Pengiriman manual — book via aplikasi kurir, lalu input
                  resi/info driver via form &quot;Tandai sudah dikirim&quot;.
                </p>
              )}
            </div>
          </section>

          {/* Bukti transfer */}
          {order.paymentProofUrl && (
            <section className="rounded-2xl border border-zinc-200 p-4 md:rounded-3xl md:p-5">
              <h2 className="font-bold text-zinc-950">Bukti Transfer</h2>
              <div className="mt-3 overflow-hidden rounded-2xl border border-zinc-100">
                <Image
                  src={order.paymentProofUrl}
                  alt="Bukti transfer"
                  width={600}
                  height={400}
                  className="w-full object-contain"
                />
              </div>
              <a
                href={order.paymentProofUrl}
                target="_blank"
                rel="noreferrer"
                className="mt-3 inline-flex w-full justify-center rounded-full border border-zinc-200 px-4 py-2 text-xs font-semibold text-zinc-700 hover:bg-zinc-50"
              >
                Lihat fullscreen →
              </a>
            </section>
          )}

          {/* Info tambahan */}
          {(order.paymentProvider ||
            order.voucherCode ||
            order.productVoucherCode ||
            order.shippingVoucherCode ||
            order.loyaltyVoucherCode ||
            order.manualVoucherCode ||
            order.notes) && (
            <section className="rounded-2xl border border-zinc-200 p-4 md:rounded-3xl md:p-5">
              <h2 className="font-bold text-zinc-950">Info tambahan</h2>
              <div className="mt-4 space-y-2 text-sm text-zinc-700">
                {/* Metode bayar — conditional render berdasarkan komposisi
                    pembayaran (saldo refund, voucher, cash). Sebelumnya
                    hanya tampilin enum mentah "MANUAL" yang misleading
                    saat user bayar full via saldo refund. */}
                <PaymentMethodLine
                  paymentProvider={order.paymentProvider}
                  refundBalanceUsed={order.refundBalanceUsed}
                  cashTotal={order.total}
                />

                {/* Voucher list — iterate semua 4 slot voucher + legacy.
                    Untuk tiap voucher yg punya entry di VoucherUsage,
                    tampilin nominal diskon-nya inline (Q1=A). */}
                {(() => {
                  const usageByCode = new Map(
                    order.voucherUsages.map((u) => [
                      u.voucher.code,
                      u.discountAmount,
                    ]),
                  );
                  const formatAmount = (code: string | null) => {
                    if (!code) return null;
                    const amt = usageByCode.get(code) ?? null;
                    return amt && amt > 0
                      ? ` (-${formatRupiah(amt)})`
                      : "";
                  };
                  return (
                    <>
                      {(order.productVoucherCode || order.voucherCode) && (
                        <p>
                          <span className="font-semibold">
                            Voucher Diskon Produk:
                          </span>{" "}
                          <span className="font-mono">
                            {order.productVoucherCode || order.voucherCode}
                          </span>
                          <span className="text-red-600">
                            {formatAmount(
                              order.productVoucherCode || order.voucherCode,
                            )}
                          </span>
                        </p>
                      )}
                      {order.shippingVoucherCode && (
                        <p>
                          <span className="font-semibold">
                            Voucher Gratis Ongkir:
                          </span>{" "}
                          <span className="font-mono">
                            {order.shippingVoucherCode}
                          </span>
                          <span className="text-red-600">
                            {formatAmount(order.shippingVoucherCode)}
                          </span>
                        </p>
                      )}
                      {order.loyaltyVoucherCode && (
                        <p>
                          <span className="font-semibold">
                            Voucher Loyalty Point:
                          </span>{" "}
                          <span className="font-mono">
                            {order.loyaltyVoucherCode}
                          </span>
                          <span className="text-red-600">
                            {formatAmount(order.loyaltyVoucherCode)}
                          </span>
                        </p>
                      )}
                      {order.manualVoucherCode && (
                        <p>
                          <span className="font-semibold">
                            Voucher Penjual (manual):
                          </span>{" "}
                          <span className="font-mono">
                            {order.manualVoucherCode}
                          </span>
                          <span className="text-red-600">
                            {formatAmount(order.manualVoucherCode)}
                          </span>
                        </p>
                      )}
                    </>
                  );
                })()}

                {order.notes && (
                  <p>
                    <span className="font-semibold">Catatan:</span> {order.notes}
                  </p>
                )}
              </div>
            </section>
          )}

          {/* ── Aksi ── */}
          {!isDone && (
            <section className="rounded-2xl border border-zinc-200 p-4 md:rounded-3xl md:p-5">
              <h2 className="font-bold text-zinc-950">Aksi</h2>

              <div className="mt-5 space-y-3">
                {/* 1. Konfirmasi pembayaran */}
                {order.paymentStatus !== "PAID" && (
                  <form action={markAsPaidAction}>
                    <button
                      type="submit"
                      className="w-full rounded-full bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700"
                    >
                      ✅ Konfirmasi pembayaran ({formatRupiah(order.total)})
                    </button>
                  </form>
                )}

                {/* 2. Proses packing (setelah bayar) */}
                {order.paymentStatus === "PAID" && (order.status === "PENDING" || order.status === "PAID") && (
                  <form action={markAsProcessingAction}>
                    <button
                      type="submit"
                      className="w-full rounded-full bg-natalo-600 px-5 py-3 text-sm font-bold text-white hover:bg-natalo-700"
                    >
                      📦 Mulai packing
                    </button>
                  </form>
                )}

                {order.paymentStatus === "PAID" && !isSelfPickup && order.courierCode && !order.biteshipOrderId && (
                  <form action={createShipmentAction}>
                    <button
                      type="submit"
                      className="w-full rounded-full bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700"
                    >
                      🚚 Booking kurir Biteship
                    </button>
                  </form>
                )}

                {/* 3. Tandai sudah dikirim (PROCESSING → SHIPPED)
                    Pakai ShippingForm dengan toggle Regular / Instant supaya
                    kurir instant (Gojek/Grab/Lalamove) yang tidak punya resi
                    bisa tetap tercatat info driver-nya. Server validate salah
                    satu wajib diisi sesuai courierType. */}
                {order.status === "PROCESSING" && !isSelfPickup && (
                  <ShippingForm
                    action={markAsShippedAction}
                    defaultTrackingNumber={order.trackingNumber || ""}
                    defaultDriverInfo={order.shippingDriverInfo || ""}
                    submitLabel="Tandai sudah dikirim"
                    variant="primary"
                  />
                )}

                {/* 4. Update info pengiriman (SHIPPED) */}
                {order.status === "SHIPPED" && !isSelfPickup && (
                  <ShippingForm
                    action={markAsShippedAction}
                    defaultTrackingNumber={order.trackingNumber || ""}
                    defaultDriverInfo={order.shippingDriverInfo || ""}
                    submitLabel="Update info pengiriman"
                    variant="secondary"
                  />
                )}

                {/* 5. Tandai selesai (SHIPPED) — OVERRIDE
                    Primary flow sekarang user-driven: customer pencet
                    "Pesanan Sudah Diterima" di app Flutter setelah paket
                    sampai → status auto DELIVERED. Tombol admin ini cuma
                    backup buat kasus:
                      - User offline lama / tidak pakai app
                      - Kurir lapor delivered tapi customer gak konfirmasi
                      - Customer minta admin tutup manual via WA
                    Note: setelah DELIVERED, window komplain/refund tutup,
                    jadi pakai dengan hati-hati. */}
                {order.status === "SHIPPED" && !isSelfPickup && (
                  <details className="rounded-2xl border border-zinc-200 bg-zinc-50 p-3">
                    <summary className="cursor-pointer text-xs font-bold text-zinc-600 hover:text-zinc-900">
                      Override: tandai selesai manual
                    </summary>
                    <p className="mt-2 text-xs text-zinc-600">
                      Sebaiknya customer yang tap &quot;Pesanan Sudah Diterima&quot; di
                      app. Pakai tombol ini hanya kalau customer tidak bisa
                      konfirmasi sendiri (offline, gak pakai app, dll).
                      Setelah selesai, refund/komplain tidak bisa dilakukan
                      lagi.
                    </p>
                    <form action={markAsDeliveredAction} className="mt-2">
                      <button
                        type="submit"
                        className="w-full rounded-full border border-emerald-300 bg-white px-5 py-2.5 text-xs font-bold text-emerald-700 hover:bg-emerald-50"
                      >
                        Tandai selesai (override)
                      </button>
                    </form>
                  </details>
                )}

                {isSelfPickup && order.paymentStatus === "PAID" && order.status === "PROCESSING" && (
                  <form action={markAsReadyForPickupAction}>
                    <button
                      type="submit"
                      className="w-full rounded-full bg-green-600 px-5 py-3 text-sm font-bold text-white hover:bg-green-700"
                    >
                      Siap Diambil
                    </button>
                  </form>
                )}

                {isSelfPickup && order.status === "READY_FOR_PICKUP" && (
                  <form action={markAsPickedUpAction}>
                    <button
                      type="submit"
                      className="w-full rounded-full bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700"
                    >
                      Serahkan Pesanan
                    </button>
                  </form>
                )}

                {/* Batalkan order — wrapped in CancelOrderButton (client)
                    untuk konfirmasi dialog yang surface nominal auto-refund
                    sebelum eksekusi. markAsCancelled sekarang otomatis
                    kredit Saldo Refund customer (lihat actions.ts). */}
                <CancelOrderButton
                  action={markAsCancelledAction}
                  orderTotal={order.total}
                  alreadyRefunded={totalRefunded}
                  refundBalanceUsed={order.refundBalanceUsed}
                  paymentStatus={order.paymentStatus}
                  orderNumber={order.orderNumber}
                />
              </div>
            </section>
          )}

          {/* Order selesai / dibatalkan */}
          {order.status === "DELIVERED" && (
            <div className="rounded-2xl bg-emerald-50 p-4 text-sm font-bold text-emerald-700 text-center">
              ✅ Order selesai
            </div>
          )}
          {order.status === "CANCELLED" && (
            <div className="rounded-2xl bg-red-50 p-4 text-sm font-bold text-red-700 text-center">
              ❌ Order dibatalkan
            </div>
          )}
        </aside>
      </div>
    </div>
  );
}

/**
 * Render "Metode bayar" line dengan logic conditional berdasarkan
 * komposisi pembayaran. Sebelumnya admin lihat "Metode bayar: MANUAL"
 * meskipun user bayar full pakai Saldo Refund — confusing.
 *
 * Logika display:
 *   1. Full saldo refund (cashTotal=0 + refundBalanceUsed>0):
 *      → "🎁 Saldo Refund (100%)"
 *   2. Hybrid (cashTotal>0 + refundBalanceUsed>0):
 *      → "🎁 Saldo Rp X + 💳 {provider} Rp Y"
 *   3. Cash only (no saldo, cashTotal>0):
 *      → "💳 {provider label}"
 *   4. Zero everything (rare — full voucher cover):
 *      → "🎁 100% Voucher (tidak ada cash + tidak ada saldo)"
 */
function PaymentMethodLine({
  paymentProvider,
  refundBalanceUsed,
  cashTotal,
}: {
  paymentProvider: string;
  refundBalanceUsed: number;
  cashTotal: number;
}) {
  // Friendly label per provider — admin lebih readable.
  const providerLabel: Record<string, string> = {
    MANUAL: "Transfer Manual",
    MIDTRANS: "Midtrans Gateway",
    XENDIT: "Xendit Gateway",
  };
  const friendlyProvider =
    providerLabel[paymentProvider] ?? paymentProvider;

  // Skenario 1: Full saldo refund cover order.
  if (cashTotal === 0 && refundBalanceUsed > 0) {
    return (
      <p>
        <span className="font-semibold">Metode bayar:</span>{" "}
        <span className="inline-flex items-center gap-1 rounded-full bg-blue-100 px-2 py-0.5 text-xs font-bold text-blue-700">
          🎁 Saldo Refund (100%)
        </span>
      </p>
    );
  }

  // Skenario 2: Hybrid — saldo refund + bayar tunai.
  if (cashTotal > 0 && refundBalanceUsed > 0) {
    return (
      <div>
        <p>
          <span className="font-semibold">Metode bayar:</span>{" "}
          <span className="inline-flex items-center gap-1 rounded-full bg-purple-100 px-2 py-0.5 text-xs font-bold text-purple-700">
            🎁💳 Hybrid Saldo + Tunai
          </span>
        </p>
        <ul className="mt-1.5 ml-3 space-y-0.5 text-xs text-zinc-600">
          <li>
            🎁 Saldo Refund:{" "}
            <span className="font-bold text-blue-700">
              {formatRupiah(refundBalanceUsed)}
            </span>
          </li>
          <li>
            💳 {friendlyProvider}:{" "}
            <span className="font-bold text-zinc-900">
              {formatRupiah(cashTotal)}
            </span>
          </li>
        </ul>
      </div>
    );
  }

  // Skenario 4: Zero everything — full voucher cover (langka).
  if (cashTotal === 0 && refundBalanceUsed === 0) {
    return (
      <p>
        <span className="font-semibold">Metode bayar:</span>{" "}
        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-bold text-emerald-700">
          🎫 100% Voucher
        </span>
      </p>
    );
  }

  // Skenario 3: Default — bayar tunai full (paling umum).
  return (
    <p>
      <span className="font-semibold">Metode bayar:</span>{" "}
      <span className="font-mono">💳 {friendlyProvider}</span>
    </p>
  );
}

