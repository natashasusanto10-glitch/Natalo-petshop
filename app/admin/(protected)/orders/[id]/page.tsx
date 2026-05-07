import Link from "next/link";
import { notFound } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";
import { ConfirmButton } from "@/components/ConfirmButton";
import {
  markAsCancelled,
  markAsDelivered,
  markAsPaid,
  markAsProcessing,
  markAsShipped,
} from "./actions";

const STATUS_LABELS: Record<string, string> = {
  PENDING: "Menunggu",
  PROCESSING: "Diproses",
  SHIPPED: "Dikirim",
  DELIVERED: "Selesai",
  CANCELLED: "Dibatalkan",
  REFUNDED: "Refund",
};

const STATUS_COLORS: Record<string, string> = {
  PENDING: "bg-amber-100 text-amber-700",
  PROCESSING: "bg-natalo-100 text-natalo-700",
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
  const markAsShippedAction = markAsShipped.bind(null, id);
  const markAsDeliveredAction = markAsDelivered.bind(null, id);
  const markAsCancelledAction = markAsCancelled.bind(null, id);

  // ── Data Fetch ──────────────────────────────────────────────
  const order = await prisma.order.findUnique({
    where: { id },
    include: { items: true },
  });

  if (!order) return notFound();

  const waNumber = order.customerPhone.startsWith("0")
    ? `62${order.customerPhone.slice(1)}`
    : order.customerPhone;

  const waText = encodeURIComponent(
    `Halo ${order.customerName}, kami dari Natalo Petshop & Aquarium. ` +
      `Order ${order.orderNumber} sudah kami terima dengan total ${formatRupiah(order.total)}.`
  );

  const isDone = order.status === "DELIVERED" || order.status === "CANCELLED" || order.status === "REFUNDED";

  return (
    <div className="mx-auto max-w-5xl px-4 py-10">
      <Link
        href="/admin/orders"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke daftar order
      </Link>

      <div className="mt-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-zinc-950">Detail Order</h1>
          <p className="mt-1 text-zinc-500">{order.orderNumber}</p>
        </div>
        <div className="flex items-center gap-3">
          <Link
            href={`/admin/orders/${order.id}/print`}
            className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-bold text-zinc-700 hover:border-zinc-500"
          >
            Print resi
          </Link>
          <span
            className={`rounded-full px-4 py-2 text-sm font-bold ${
              PAY_COLORS[order.paymentStatus] ?? "bg-zinc-100 text-zinc-600"
            }`}
          >
            {PAY_LABELS[order.paymentStatus] ?? order.paymentStatus}
          </span>
          <span
            className={`rounded-full px-4 py-2 text-sm font-bold ${
              STATUS_COLORS[order.status] ?? "bg-zinc-100 text-zinc-600"
            }`}
          >
            {STATUS_LABELS[order.status] ?? order.status}
          </span>
        </div>
      </div>

      <div className="mt-8 grid gap-6 lg:grid-cols-[1fr_340px]">
        {/* ── Produk ── */}
        <section className="rounded-3xl border border-zinc-200 p-5">
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
          </div>
        </section>

        {/* ── Sidebar ── */}
        <aside className="space-y-5">
          {/* Customer */}
          <section className="rounded-3xl border border-zinc-200 p-5">
            <h2 className="font-bold text-zinc-950">Customer</h2>
            <div className="mt-4 space-y-2 text-sm text-zinc-700">
              <p>
                <span className="font-semibold">Nama:</span> {order.customerName}
              </p>
              <p>
                <span className="font-semibold">WhatsApp:</span> {order.customerPhone}
              </p>
              {order.customerEmail && (
                <p>
                  <span className="font-semibold">Email:</span> {order.customerEmail}
                </p>
              )}
            </div>
            <a
              href={`https://wa.me/${waNumber}?text=${waText}`}
              target="_blank"
              rel="noreferrer"
              className="mt-5 inline-flex w-full justify-center rounded-full bg-green-600 px-5 py-3 text-sm font-bold text-white hover:bg-green-700"
            >
              💬 Chat customer
            </a>
          </section>

          {/* Pengiriman */}
          <section className="rounded-3xl border border-zinc-200 p-5">
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
              <p>
                <span className="font-semibold">No. Resi:</span>{" "}
                {order.trackingNumber ? (
                  <span className="font-mono">{order.trackingNumber}</span>
                ) : (
                  <span className="text-zinc-400">-</span>
                )}
              </p>
            </div>
          </section>

          {/* Info tambahan */}
          {(order.paymentProvider || order.voucherCode || order.notes) && (
            <section className="rounded-3xl border border-zinc-200 p-5">
              <h2 className="font-bold text-zinc-950">Info tambahan</h2>
              <div className="mt-4 space-y-2 text-sm text-zinc-700">
                <p>
                  <span className="font-semibold">Metode bayar:</span>{" "}
                  {order.paymentProvider}
                </p>
                {order.voucherCode && (
                  <p>
                    <span className="font-semibold">Voucher:</span> {order.voucherCode}
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
            <section className="rounded-3xl border border-zinc-200 p-5">
              <h2 className="font-bold text-zinc-950">Aksi</h2>

              <div className="mt-5 space-y-3">
                {/* 1. Konfirmasi pembayaran */}
                {order.paymentStatus !== "PAID" && (
                  <ConfirmButton
                    action={markAsPaidAction}
                    variant="primary"
                    confirmTitle="Konfirmasi pembayaran"
                    confirmMessage={`Pastikan pembayaran sebesar ${formatRupiah(
                      order.total
                    )} sudah masuk. Customer akan menerima email konfirmasi.`}
                    confirmLabel="Ya, sudah lunas"
                  >
                    ✅ Konfirmasi pembayaran
                  </ConfirmButton>
                )}

                {/* 2. Proses packing (setelah bayar, masih PENDING) */}
                {order.paymentStatus === "PAID" && order.status === "PENDING" && (
                  <ConfirmButton
                    action={markAsProcessingAction}
                    variant="primary"
                    className="!bg-natalo-600 hover:!bg-natalo-700"
                    confirmTitle="Mulai packing"
                    confirmMessage="Order akan ditandai sedang diproses. Lanjutkan?"
                    confirmLabel="Ya, mulai packing"
                  >
                    📦 Mulai packing
                  </ConfirmButton>
                )}

                {/* 3. Tandai sudah dikirim (PROCESSING → SHIPPED) */}
                {order.status === "PROCESSING" && (
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
                {order.status === "SHIPPED" && (
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
                {order.status === "SHIPPED" && (
                  <ConfirmButton
                    action={markAsDeliveredAction}
                    variant="success"
                    confirmTitle="Tandai order selesai"
                    confirmMessage="Pastikan paket sudah benar-benar diterima customer. Setelah selesai, status tidak bisa diubah lagi."
                    confirmLabel="Ya, selesai"
                  >
                    ✅ Tandai selesai
                  </ConfirmButton>
                )}

                {/* Batalkan - paling perlu confirm */}
                <ConfirmButton
                  action={markAsCancelledAction}
                  variant="danger"
                  confirmTitle="Batalkan order ini?"
                  confirmMessage={
                    order.status === "SHIPPED" || order.status === "DELIVERED"
                      ? "Paket sudah dikirim/diterima - stock TIDAK akan otomatis dikembalikan. Anda harus manual handle return/refund. Lanjutkan?"
                      : "Stock akan dikembalikan dan customer akan menerima email pembatalan. Aksi ini tidak bisa di-undo."
                  }
                  confirmLabel="Ya, batalkan"
                >
                  Batalkan order
                </ConfirmButton>
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
