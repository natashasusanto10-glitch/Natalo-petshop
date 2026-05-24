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
} from "./actions";

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
  const createShipmentAction = createShipment.bind(null, id);

  const issueRefundToWalletAction = issueRefundToWallet.bind(null, id);

  // ── Data Fetch ──────────────────────────────────────────────
  const order = await prisma.order.findUnique({
    where: { id },
    include: {
      items: true,
      refundCases: {
        orderBy: { createdAt: "desc" },
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

      <div className="mt-5 grid gap-4 md:mt-8 md:gap-6 lg:grid-cols-[1fr_340px]">
        {/* ── Produk ── */}
        <section className="rounded-2xl border border-zinc-200 p-4 md:rounded-3xl md:p-5">
          <h2 className="font-bold text-zinc-950">Produk dibeli</h2>

          <div className="mt-4 space-y-3">
            {order.items.map((item) => (
              <div
                key={item.id}
                className="flex justify-between gap-4 rounded-2xl bg-zinc-50 p-4 text-sm"
              >
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
            ))}
          </div>

          <div className="mt-6 space-y-2 border-t border-zinc-100 pt-4 text-sm">
            <div className="flex justify-between text-zinc-600">
              <span>Subtotal</span>
              <span>{formatRupiah(order.subtotal)}</span>
            </div>
            <div className="flex justify-between text-zinc-600">
              <span>Ongkir</span>
              <span>{formatRupiah(order.shippingCost)}</span>
            </div>
            {order.discount > 0 && (
              <div className="flex justify-between text-zinc-600">
                <span>Diskon</span>
                <span>-{formatRupiah(order.discount)}</span>
              </div>
            )}
            <div className="flex justify-between text-lg font-black text-zinc-950">
              <span>Total</span>
              <span>{formatRupiah(order.total)}</span>
            </div>
            {totalRefunded > 0 && (
              <div className="flex justify-between text-blue-700">
                <span>Sudah di-refund</span>
                <span>-{formatRupiah(totalRefunded)}</span>
              </div>
            )}
          </div>

          {/* ── Saldo Refund Section ── */}
          <details className="mt-6 rounded-2xl border border-blue-200 bg-blue-50/50 p-4">
            <summary className="cursor-pointer font-semibold text-blue-900">
              💰 Refund ke Saldo Refund User
            </summary>
            <p className="mt-2 text-xs text-zinc-600">
              Kredit saldo refund user untuk kasus produk kosong, partial
              cancel, atau return approved. Saldo akan masuk instant dan
              bisa user pakai di checkout berikutnya.
            </p>
            <form
              action={issueRefundToWalletAction}
              className="mt-3 space-y-3 text-sm"
            >
              <div>
                <label className="block text-xs font-semibold text-zinc-700">
                  Item (opsional)
                </label>
                <select
                  name="itemId"
                  className="mt-1 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
                  defaultValue=""
                >
                  <option value="">— Seluruh order —</option>
                  {order.items.map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.name} ({item.quantity}× {formatRupiah(item.price)})
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-xs font-semibold text-zinc-700">
                  Nominal refund (Rp)
                </label>
                <input
                  type="number"
                  name="amount"
                  min={1}
                  step={1}
                  required
                  placeholder="32000"
                  className="mt-1 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
                />
                <p className="mt-1 text-[11px] text-zinc-500">
                  Tips: kurangi alokasi voucher proporsional kalau order
                  pakai voucher (lihat spec rumus).
                </p>
              </div>
              <div>
                <label className="block text-xs font-semibold text-zinc-700">
                  Alasan refund
                </label>
                <select
                  name="reason"
                  required
                  defaultValue="OUT_OF_STOCK"
                  className="mt-1 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
                >
                  <option value="OUT_OF_STOCK">Produk kosong</option>
                  <option value="PARTIAL_CANCEL">Dibatalkan sebagian</option>
                  <option value="RETURN_APPROVED">Return disetujui</option>
                  <option value="ORDER_CANCELLED">Order dibatalkan</option>
                  <option value="OTHER">Lainnya</option>
                </select>
              </div>
              <div>
                <label className="block text-xs font-semibold text-zinc-700">
                  Catatan untuk user (opsional)
                </label>
                <textarea
                  name="adminNote"
                  maxLength={500}
                  rows={2}
                  placeholder="Stok kosong saat packing, maaf ya!"
                  className="mt-1 w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
                />
              </div>
              <button
                type="submit"
                className="w-full rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700"
              >
                Kredit Saldo Refund
              </button>
            </form>

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
              {order.biteshipOrderId && (
                <p>
                  <span className="font-semibold">Biteship ID:</span>{" "}
                  <span className="font-mono">{order.biteshipOrderId}</span>
                </p>
              )}
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
                <p>
                  <span className="font-semibold">Metode bayar:</span>{" "}
                  {order.paymentProvider}
                </p>
                {(order.productVoucherCode || order.voucherCode) && (
                  <p>
                    <span className="font-semibold">Voucher Diskon Produk:</span>{" "}
                    {order.productVoucherCode || order.voucherCode}
                  </p>
                )}
                {order.shippingVoucherCode && (
                  <p>
                    <span className="font-semibold">Voucher Gratis Ongkir:</span>{" "}
                    {order.shippingVoucherCode}
                  </p>
                )}
                {order.loyaltyVoucherCode && (
                  <p>
                    <span className="font-semibold">Voucher Loyalty Point:</span>{" "}
                    {order.loyaltyVoucherCode}
                  </p>
                )}
                {order.manualVoucherCode && (
                  <p>
                    <span className="font-semibold">Voucher Penjual (manual):</span>{" "}
                    {order.manualVoucherCode}
                  </p>
                )}
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

                {/* 3. Tandai sudah dikirim (PROCESSING → SHIPPED) */}
                {order.status === "PROCESSING" && !isSelfPickup && (
                  <form action={markAsShippedAction} className="space-y-3">
                    <input
                      name="trackingNumber"
                      placeholder="Nomor resi (opsional)"
                      defaultValue={order.trackingNumber || ""}
                      className="w-full rounded-2xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
                    />
                    <button className="w-full rounded-full bg-indigo-600 px-5 py-3 text-sm font-bold text-white hover:bg-indigo-700">
                      🚚 Tandai sudah dikirim
                    </button>
                  </form>
                )}

                {/* 4. Update resi (SHIPPED) */}
                {order.status === "SHIPPED" && !isSelfPickup && (
                  <form action={markAsShippedAction} className="space-y-3">
                    <input
                      name="trackingNumber"
                      placeholder="Update nomor resi"
                      defaultValue={order.trackingNumber || ""}
                      className="w-full rounded-2xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
                    />
                    <button
                      type="submit"
                      className="w-full rounded-full border border-zinc-300 px-5 py-3 text-sm font-bold hover:border-zinc-500"
                    >
                      Update resi
                    </button>
                  </form>
                )}

                {/* 5. Tandai selesai (SHIPPED) */}
                {order.status === "SHIPPED" && !isSelfPickup && (
                  <form action={markAsDeliveredAction}>
                    <button
                      type="submit"
                      className="w-full rounded-full bg-emerald-600 px-5 py-3 text-sm font-bold text-white hover:bg-emerald-700"
                    >
                      ✅ Tandai selesai
                    </button>
                  </form>
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

                {/* Batalkan */}
                <form action={markAsCancelledAction}>
                  <button
                    type="submit"
                    className="w-full rounded-full border border-red-300 bg-red-50 px-5 py-3 text-sm font-bold text-red-700 hover:bg-red-100"
                  >
                    Batalkan order
                  </button>
                </form>
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
