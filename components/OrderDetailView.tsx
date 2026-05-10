"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { formatRupiah } from "@/lib/format";
import type { SerializedOrderDetail } from "@/lib/order-detail";
import { PaymentProofUpload } from "@/components/PaymentProofUpload";
import { PushSubscribe } from "@/components/PushSubscribe";
import { ExternalLink } from "@/components/ExternalLink";

const BANK_ACCOUNTS: Record<string, { bankName: string; accountNumber: string; accountName: string }> = {
  BCA_NATASHA: {
    bankName: "BCA",
    accountNumber: "8280277046",
    accountName: "NATASHA",
  },
  BCA_NL_PET: {
    bankName: "BCA",
    accountNumber: "0987654321",
    accountName: "NL Pet Shop",
  },
};

const STATUS_LABEL: Record<string, string> = {
  PENDING: "Menunggu pembayaran",
  PAID: "Pembayaran dikonfirmasi",
  PROCESSING: "Pesanan diproses",
  SHIPPED: "Pesanan dikirim",
  DELIVERED: "Pesanan selesai",
  CANCELLED: "Pesanan dibatalkan",
  REFUNDED: "Refund",
};

const PAYMENT_STATUS_LABEL: Record<string, string> = {
  UNPAID: "Belum bayar",
  PENDING: "Menunggu pembayaran",
  PAID: "Lunas",
  FAILED: "Gagal",
  EXPIRED: "Kedaluwarsa",
  REFUNDED: "Dikembalikan",
};

const TIMELINE = [
  { key: "PENDING", label: "Pesanan dibuat" },
  { key: "WAITING_PAYMENT", label: "Menunggu pembayaran" },
  { key: "PAID", label: "Pembayaran dikonfirmasi" },
  { key: "PROCESSING", label: "Pesanan diproses" },
  { key: "SHIPPED", label: "Pesanan dikirim" },
  { key: "DELIVERED", label: "Pesanan selesai" },
];

const STATUS_STEP_INDEX: Record<string, number> = {
  PENDING: 1,
  PAID: 2,
  PROCESSING: 3,
  SHIPPED: 4,
  DELIVERED: 5,
};

const COURIER_TRACKING: Record<string, string> = {
  jne: "https://www.jne.co.id/id/tracking/trace",
  jnt: "https://www.jet.co.id/track",
  "j&t": "https://www.jet.co.id/track",
  sicepat: "https://www.sicepat.com/checkAwb",
  anteraja: "https://anteraja.id/tracking",
  pos: "https://www.posindonesia.co.id/id/tracking",
  tiki: "https://www.tiki.id/id/tracking",
  ninja: "https://www.ninjaxpress.co/id-id/tracking",
};

function useCopyToast() {
  const [msg, setMsg] = useState<string | null>(null);

  useEffect(() => {
    if (!msg) return;
    const id = setTimeout(() => setMsg(null), 1800);
    return () => clearTimeout(id);
  }, [msg]);

  function copy(value: string, label: string) {
    navigator.clipboard.writeText(value).then(() => setMsg(label)).catch(() => {});
  }

  return { msg, copy };
}

function StatusTimeline({ order }: { order: SerializedOrderDetail }) {
  const currentIndex = order.status === "CANCELLED" ? -1 : STATUS_STEP_INDEX[order.status] ?? 0;

  if (order.status === "CANCELLED") {
    return (
      <div className="rounded-3xl border border-red-100 bg-red-50 p-5">
        <p className="text-sm font-black text-red-700">Pesanan dibatalkan</p>
        <p className="mt-1 text-sm text-red-600">Hubungi admin Natalo jika kamu membutuhkan bantuan lanjutan.</p>
      </div>
    );
  }

  return (
    <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-sm font-black text-gray-900">Status Pesanan</p>
          <p className="mt-1 text-xs text-gray-500">Update otomatis saat status berubah.</p>
        </div>
        <span className="rounded-full bg-blue-50 px-3 py-1 text-xs font-bold text-blue-700">
          {STATUS_LABEL[order.status] ?? order.status}
        </span>
      </div>

      <div className="mt-5 space-y-4">
        {TIMELINE.map((step, index) => {
          const done = index <= currentIndex;
          const active = index === currentIndex;
          return (
            <div key={step.key} className="flex gap-3">
              <div className="flex flex-col items-center">
                <span className={`h-4 w-4 rounded-full border-2 ${done ? "border-blue-600 bg-blue-600" : "border-gray-300 bg-white"}`} />
                {index < TIMELINE.length - 1 && <span className={`mt-1 h-7 w-px ${done ? "bg-blue-200" : "bg-gray-200"}`} />}
              </div>
              <div>
                <p className={`text-sm font-bold ${done ? "text-gray-900" : "text-gray-400"}`}>{step.label}</p>
                {active && <p className="mt-0.5 text-xs text-blue-600">Status saat ini</p>}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function CourierTracking({ order }: { order: SerializedOrderDetail }) {
  if (!order.trackingNumber) return null;
  const courierCode = order.courierCode ?? "";
  const fallbackUrl = order.biteshipTrackingUrl;
  const url = fallbackUrl || COURIER_TRACKING[courierCode.toLowerCase()];

  return (
    <div className="mt-3 rounded-2xl bg-blue-50 p-3">
      <p className="text-xs font-semibold text-blue-700">
        Nomor Resi: <span className="font-black">{order.trackingNumber}</span>
      </p>
      {url && (
        <ExternalLink href={url} className="mt-2 inline-flex text-xs font-bold text-blue-700 hover:underline">
          Lacak pengiriman
        </ExternalLink>
      )}
    </div>
  );
}

export function OrderDetailView({
  initialOrder,
  token,
}: {
  initialOrder: SerializedOrderDetail;
  token?: string | null;
}) {
  const [order, setOrder] = useState(initialOrder);
  const [refreshError, setRefreshError] = useState("");
  const { msg: copyMsg, copy } = useCopyToast();

  useEffect(() => {
    let cancelled = false;
    const params = token ? `?token=${encodeURIComponent(token)}` : "";

    async function refresh() {
      try {
        const res = await fetch(`/api/orders/${encodeURIComponent(initialOrder.orderNumber)}${params}`, {
          cache: "no-store",
        });
        const data = await res.json();
        if (!cancelled && res.ok && data.order) {
          setOrder(data.order);
          setRefreshError("");
        } else if (!cancelled && !res.ok) {
          setRefreshError(data.message || "Gagal memperbarui status pesanan.");
        }
      } catch {
        if (!cancelled) setRefreshError("Status belum bisa diperbarui. Data terakhir tetap ditampilkan.");
      }
    }

    const id = window.setInterval(refresh, 15000);
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, [initialOrder.orderNumber, token]);

  const tanggal = useMemo(
    () =>
      new Date(order.createdAt).toLocaleString("id-ID", {
        day: "numeric",
        month: "long",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      }),
    [order.createdAt]
  );
  const bank = order.manualBank ? BANK_ACCOUNTS[order.manualBank] : null;
  const totalTransfer = order.total + (order.uniqueCode ?? 0);
  const waNumber = (process.env.NEXT_PUBLIC_WA_NUMBER ?? process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ?? "").replace("+", "");
  const waText = encodeURIComponent(
    order.paymentProvider === "MANUAL" && bank
      ? `Halo Admin Natalo, saya ingin konfirmasi pembayaran pesanan ${order.orderNumber}. Nama: ${order.customerName}. Total transfer: ${formatRupiah(totalTransfer)}.`
      : `Halo Natalo Petshop, saya ingin bertanya tentang pesanan ${order.orderNumber}.`
  );

  return (
    <div className="mx-auto max-w-4xl px-4 pb-28 pt-4 md:py-10">
      {copyMsg && (
        <div className="fixed bottom-24 left-1/2 z-50 -translate-x-1/2 rounded-full bg-gray-950 px-4 py-2 text-xs font-bold text-white shadow-lg md:bottom-6">
          {copyMsg}
        </div>
      )}

      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.2em] text-blue-600">Pesanan Saya</p>
          <h1 className="mt-1 text-2xl font-black tracking-tight text-gray-950 md:text-3xl">Detail Pesanan</h1>
        </div>
        <Link href="/member/orders" className="rounded-full border border-gray-200 px-4 py-2 text-xs font-bold text-gray-700 hover:border-blue-300 hover:text-blue-700">
          Pesanan Saya
        </Link>
      </div>

      {refreshError && (
        <p className="mt-4 rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-700">{refreshError}</p>
      )}

      <div className="mt-5 grid gap-5 lg:grid-cols-[1.15fr_0.85fr]">
        <div className="space-y-5">
          <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-widest text-gray-400">Nomor Pesanan</p>
                <p className="mt-1 text-xl font-black text-gray-950">{order.orderNumber}</p>
                <p className="mt-1 text-sm text-gray-500">{tanggal}</p>
              </div>
              <button
                type="button"
                onClick={() => copy(order.orderNumber, "Nomor pesanan tersalin")}
                className="rounded-full bg-blue-50 px-4 py-2 text-xs font-bold text-blue-700 hover:bg-blue-100"
              >
                Salin Nomor
              </button>
            </div>

            <div className="mt-5 grid gap-3 text-sm text-gray-700">
              <p><span className="font-semibold">Nama Customer:</span> {order.customerName}</p>
              <p><span className="font-semibold">Status Pembayaran:</span> {PAYMENT_STATUS_LABEL[order.paymentStatus] ?? order.paymentStatus}</p>
              <p><span className="font-semibold">Metode Pembayaran:</span> {order.paymentProvider === "MANUAL" ? "Transfer Manual" : order.paymentProvider}</p>
            </div>
          </div>

          <StatusTimeline order={order} />

          <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
            <p className="font-black text-gray-950">Alamat Pengiriman</p>
            <div className="mt-3 space-y-1 text-sm text-gray-700">
              <p>{order.customerName} · {order.customerPhone}</p>
              <p>{order.shippingAddress}</p>
              <p>
                {[order.shippingCity, order.shippingPostalCode].filter(Boolean).join(", ") || "-"}
              </p>
              {order.shippingPinpointAddress && <p className="text-xs text-green-700">Pinpoint: {order.shippingPinpointAddress}</p>}
            </div>
            {(order.courierCode || order.courierService) && (
              <p className="mt-3 text-sm text-gray-700">
                <span className="font-semibold">Kurir:</span> {[order.courierCode?.toUpperCase(), order.courierService].filter(Boolean).join(" ")}
              </p>
            )}
            <CourierTracking order={order} />
          </div>

          <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
            <p className="font-black text-gray-950">Produk</p>
            <div className="mt-4 space-y-3">
              {order.items.map((item) => (
                <div key={item.id} className="flex justify-between gap-4 text-sm">
                  <div>
                    <p className="font-semibold text-gray-800">{item.name}</p>
                    {item.variantLabel && <p className="text-xs text-gray-400">{item.variantLabel}</p>}
                    <p className="text-xs text-gray-500">Qty {item.quantity}</p>
                  </div>
                  <span className="font-bold text-gray-900">{formatRupiah(item.price * item.quantity)}</span>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="space-y-5">
          <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
            <p className="font-black text-gray-950">Ringkasan Pembayaran</p>
            <div className="mt-4 space-y-2 text-sm">
              <div className="flex justify-between text-gray-600"><span>Subtotal Produk</span><span>{formatRupiah(order.subtotal)}</span></div>
              <div className="flex justify-between text-gray-600"><span>Ongkos Kirim</span><span>{formatRupiah(order.shippingCost)}</span></div>
              {order.discount > 0 && <div className="flex justify-between text-green-600"><span>Diskon</span><span>-{formatRupiah(order.discount)}</span></div>}
              <div className="flex justify-between border-t pt-3 text-base font-black text-gray-950">
                <span>Total Pembayaran</span><span>{formatRupiah(order.total)}</span>
              </div>
              {order.paymentProvider === "MANUAL" && order.uniqueCode !== null && (
                <div className="flex justify-between text-sm font-bold text-blue-700">
                  <span>Total Transfer</span><span>{formatRupiah(totalTransfer)}</span>
                </div>
              )}
            </div>
          </div>

          {order.paymentProvider === "MANUAL" && bank && order.paymentStatus !== "PAID" && (
            <div className="rounded-3xl border border-blue-100 bg-blue-50 p-5">
              <p className="font-black text-gray-950">Instruksi Transfer Manual</p>
              <div className="mt-4 rounded-2xl bg-white p-4">
                <p className="text-xs text-gray-500">Bank tujuan</p>
                <p className="mt-1 text-lg font-black text-gray-950">{bank.bankName}</p>
                <div className="mt-3 flex items-center justify-between gap-3 rounded-xl bg-gray-50 px-3 py-2">
                  <p className="font-mono text-base font-bold tracking-wide text-gray-950">{bank.accountNumber}</p>
                  <button type="button" onClick={() => copy(bank.accountNumber, "Nomor rekening tersalin")} className="text-xs font-bold text-blue-700 hover:underline">
                    Salin
                  </button>
                </div>
                <p className="mt-1 text-xs text-gray-500">a/n {bank.accountName}</p>
              </div>
              <div className="mt-3 rounded-2xl bg-white p-4">
                <p className="text-xs text-gray-500">Transfer sesuai nominal ini</p>
                <div className="mt-1 flex items-center justify-between gap-3">
                  <p className="text-2xl font-black text-blue-700">{formatRupiah(totalTransfer)}</p>
                  <button type="button" onClick={() => copy(String(totalTransfer), "Total transfer tersalin")} className="text-xs font-bold text-blue-700 hover:underline">
                    Salin
                  </button>
                </div>
                {order.uniqueCode !== null && (
                  <p className="mt-2 text-xs text-gray-600">Termasuk kode unik {order.uniqueCode} untuk mempercepat verifikasi.</p>
                )}
              </div>
              <PaymentProofUpload orderNumber={order.orderNumber} />
              {waNumber && (
                <ExternalLink
                  href={`https://wa.me/${waNumber}?text=${waText}`}
                  className="mt-3 inline-flex w-full justify-center rounded-full bg-blue-600 px-5 py-3 text-sm font-black text-white hover:bg-blue-700"
                >
                  Konfirmasi via WhatsApp
                </ExternalLink>
              )}
            </div>
          )}

          {order.paymentStatus !== "PAID" && order.paymentUrl && (
            <a href={order.paymentUrl} className="inline-flex w-full justify-center rounded-full bg-blue-600 px-5 py-3 text-sm font-black text-white hover:bg-blue-700">
              Bayar Sekarang
            </a>
          )}

          <PushSubscribe />
        </div>
      </div>
    </div>
  );
}
