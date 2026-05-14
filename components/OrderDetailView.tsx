"use client";

import { useEffect, useMemo, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { FiPackage } from "react-icons/fi";
import { formatRupiah } from "@/lib/format";
import {
  getFirstReviewableOrderItem,
  type SerializedOrderDetail,
} from "@/lib/order-detail";
import { PaymentProofUpload } from "@/components/PaymentProofUpload";
import { ExternalLink } from "@/components/ExternalLink";
import { trackSuccessfulOrder } from "@/lib/app-rating";
import { PageStatusBar } from "@/components/PageStatusBar";
import { ReviewModal } from "@/components/ReviewModal";
import { SELF_PICKUP_STORE } from "@/lib/self-pickup";

const BANK_ACCOUNTS: Record<
  string,
  { bankName: string; accountNumber: string; accountName: string }
> = {
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
  READY_FOR_PICKUP: "Pesanan siap diambil",
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

const SELF_PICKUP_TIMELINE = [
  { key: "PENDING", label: "Pesanan dibuat" },
  { key: "WAITING_PAYMENT", label: "Menunggu pembayaran" },
  { key: "PAID", label: "Pembayaran dikonfirmasi" },
  { key: "PROCESSING", label: "Pesanan disiapkan" },
  { key: "READY_FOR_PICKUP", label: "Siap diambil" },
  { key: "DELIVERED", label: "Pesanan selesai" },
];

const STATUS_STEP_INDEX: Record<string, number> = {
  PENDING: 1,
  PAID: 2,
  PROCESSING: 3,
  READY_FOR_PICKUP: 4,
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
    navigator.clipboard
      .writeText(value)
      .then(() => setMsg(label))
      .catch(() => {});
  }

  return { msg, copy };
}

function StatusTimeline({ order }: { order: SerializedOrderDetail }) {
  const steps = order.orderType === "SELF_PICKUP" ? SELF_PICKUP_TIMELINE : TIMELINE;
  const currentIndex =
    order.status === "CANCELLED" ? -1 : STATUS_STEP_INDEX[order.status] ?? 0;

  if (order.status === "CANCELLED") {
    return (
      <div className="rounded-3xl border border-red-100 bg-red-50 p-5">
        <p className="text-sm font-black text-red-700">Pesanan dibatalkan</p>
        <p className="mt-1 text-sm text-red-600">
          Hubungi admin Natalo jika kamu membutuhkan bantuan lanjutan.
        </p>
      </div>
    );
  }

  if (order.orderType === "SELF_PICKUP" && order.status === "READY_FOR_PICKUP") {
    return (
      <div className="rounded-3xl border border-green-100 bg-green-50 p-5">
        <p className="text-sm font-black text-green-800">Pesanan Siap Diambil</p>
        <p className="mt-2 text-sm leading-6 text-green-700">
          Pesanan kamu sudah siap. Tunjukkan kode pengambilan ke kasir saat pickup.
        </p>
        {order.pickupCode && (
          <div className="mt-4 rounded-2xl bg-white px-4 py-4 text-center">
            <p className="text-xs font-bold text-gray-500">Kode Pengambilan</p>
            <p className="mt-1 font-mono text-3xl font-black tracking-widest text-green-800">
              {order.pickupCode}
            </p>
          </div>
        )}
      </div>
    );
  }

  if (order.orderType === "SELF_PICKUP") {
    return (
      <div className="rounded-3xl border border-blue-100 bg-blue-50 p-5">
        <p className="text-sm font-black text-blue-900">Pesanan Sedang Disiapkan</p>
        <p className="mt-2 text-sm leading-6 text-blue-800">
          Pesanan kamu sedang disiapkan oleh toko. Kami akan memberi notifikasi saat pesanan sudah siap diambil.
        </p>
      </div>
    );
  }

  return (
    <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-sm font-black text-gray-900">Status Pesanan</p>
          <p className="mt-1 text-xs text-gray-500">
            Update otomatis saat status berubah.
          </p>
        </div>
        <span className="rounded-full bg-blue-50 px-3 py-1 text-xs font-bold text-blue-700">
          {STATUS_LABEL[order.status] ?? order.status}
        </span>
      </div>

      <div className="mt-5 space-y-4">
        {steps.map((step, index) => {
          const done = index <= currentIndex;
          const active = index === currentIndex;
          return (
            <div key={step.key} className="flex gap-3">
              <div className="flex flex-col items-center">
                <span
                  className={`h-4 w-4 rounded-full border-2 ${
                    done
                      ? "border-blue-600 bg-blue-600"
                      : "border-gray-300 bg-white"
                  }`}
                />
                {index < steps.length - 1 && (
                  <span
                    className={`mt-1 h-7 w-px ${
                      done ? "bg-blue-200" : "bg-gray-200"
                    }`}
                  />
                )}
              </div>
              <div>
                <p
                  className={`text-sm font-bold ${
                    done ? "text-gray-900" : "text-gray-400"
                  }`}
                >
                  {step.label}
                </p>
                {active && (
                  <p className="mt-0.5 text-xs text-blue-600">
                    Status saat ini
                  </p>
                )}
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
        <ExternalLink
          href={url}
          className="mt-2 inline-flex text-xs font-bold text-blue-700 hover:underline"
        >
          Lacak pengiriman
        </ExternalLink>
      )}
    </div>
  );
}

function OrderFollowUpCard({
  order,
  canReview,
  reviewableItem,
  onReview,
}: {
  order: SerializedOrderDetail;
  canReview: boolean;
  reviewableItem: SerializedOrderDetail["items"][number] | null;
  onReview: (item: SerializedOrderDetail["items"][number]) => void;
}) {
  if (order.status === "DELIVERED") {
    return (
      <div className="rounded-3xl border border-green-100 bg-green-50 p-5">
        <p className="text-sm font-black text-green-800">Pesanan Selesai</p>
        <p className="mt-2 text-sm leading-6 text-green-700">
          {reviewableItem
            ? "Yuk beri ulasan untuk produk di pesanan ini."
            : canReview
            ? "Terima kasih, semua produk di pesanan ini sudah direview."
            : "Terima kasih sudah berbelanja di Natalo Petshop."}
        </p>
        {reviewableItem && (
          <button
            type="button"
            onClick={() => onReview(reviewableItem)}
            className="mt-4 inline-flex w-full items-center justify-center rounded-full bg-green-700 px-5 py-3 text-sm font-black text-white hover:bg-green-800"
          >
            Beri Ulasan Produk
          </button>
        )}
      </div>
    );
  }

  if (order.status === "CANCELLED") {
    return (
      <div className="rounded-3xl border border-red-100 bg-red-50 p-5">
        <p className="text-sm font-black text-red-800">Pesanan Dibatalkan</p>
        <p className="mt-2 text-sm leading-6 text-red-700">
          Hubungi admin Natalo jika kamu membutuhkan bantuan lanjutan.
        </p>
      </div>
    );
  }

  return (
    <div className="rounded-3xl border border-blue-100 bg-blue-50 p-5">
      <p className="text-sm font-black text-blue-900">
        {STATUS_LABEL[order.status] ?? "Status pesanan"}
      </p>
      <p className="mt-2 text-sm leading-6 text-blue-800">
        Pesanan sedang diproses. Kami akan mengirim update melalui notifikasi
        aplikasi.
      </p>
      {order.trackingNumber && (
        <div className="mt-4 rounded-2xl bg-white/80 px-4 py-3 text-sm text-blue-900">
          <p className="font-semibold">Nomor resi</p>
          <p className="mt-1 font-mono font-black">{order.trackingNumber}</p>
        </div>
      )}
    </div>
  );
}

export function OrderDetailView({
  initialOrder,
  token,
  canReview = false,
}: {
  initialOrder: SerializedOrderDetail;
  token?: string | null;
  canReview?: boolean;
}) {
  const [order, setOrder] = useState(initialOrder);
  const [refreshError, setRefreshError] = useState("");
  const [reviewItem, setReviewItem] = useState<
    SerializedOrderDetail["items"][number] | null
  >(null);
  const { msg: copyMsg, copy } = useCopyToast();

  // App Store rating prompt — trigger setelah order ke-3 berhasil dibayar.
  // Dedup per-order ID via localStorage di lib/app-rating.ts. Apple internal
  // rate-limit max 3 prompts/year/user, jadi aman dipanggil multiple times.
  useEffect(() => {
    if (order.paymentStatus === "PAID") {
      // Delay sedikit biar gak prompt langsung saat halaman load — kasih
      // user beberapa detik nikmati confirmation success page dulu.
      const t = setTimeout(() => {
        void trackSuccessfulOrder(order.id);
      }, 3000);
      return () => clearTimeout(t);
    }
  }, [order.paymentStatus, order.id]);

  useEffect(() => {
    let cancelled = false;
    const params = token ? `?token=${encodeURIComponent(token)}` : "";

    async function refresh() {
      try {
        const res = await fetch(
          `/api/orders/${encodeURIComponent(
            initialOrder.orderNumber
          )}${params}`,
          {
            cache: "no-store",
          }
        );
        const data = await res.json();
        if (!cancelled && res.ok && data.order) {
          setOrder(data.order);
          setRefreshError("");
        } else if (!cancelled && !res.ok) {
          setRefreshError(data.message || "Gagal memperbarui status pesanan.");
        }
      } catch {
        if (!cancelled)
          setRefreshError(
            "Status belum bisa diperbarui. Data terakhir tetap ditampilkan."
          );
      }
    }

    // Polling tiap 15s untuk auto-update status. Pause saat tab/app tidak
    // visible — di iOS native app yang background, polling akan drain
    // battery + waste API calls untuk update yang user tidak lihat.
    let id: number | null = null;
    function start() {
      if (id !== null) return;
      id = window.setInterval(refresh, 15000);
    }
    function stop() {
      if (id !== null) {
        window.clearInterval(id);
        id = null;
      }
    }
    function onVisibilityChange() {
      if (document.hidden) {
        stop();
      } else {
        // Saat kembali visible, langsung refresh sekali (sync state cepat)
        // lalu resume interval.
        void refresh();
        start();
      }
    }

    if (!document.hidden) start();
    document.addEventListener("visibilitychange", onVisibilityChange);
    return () => {
      cancelled = true;
      stop();
      document.removeEventListener("visibilitychange", onVisibilityChange);
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
  const paymentLabel =
    order.paymentProvider === "MANUAL" ? "Transfer Manual" : order.paymentProvider;
  const waNumber = (
    process.env.NEXT_PUBLIC_WA_NUMBER ??
    process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ??
    ""
  ).replace("+", "");
  const waText = encodeURIComponent(
    order.paymentProvider === "MANUAL" && bank
      ? `Halo Admin Natalo, saya ingin konfirmasi pembayaran pesanan ${
          order.orderNumber
        }. Nama: ${order.customerName}. Total transfer: ${formatRupiah(
          totalTransfer
        )}.`
      : `Halo Natalo Petshop, saya ingin bertanya tentang pesanan ${order.orderNumber}.`
  );
  const showReviewActions = canReview && order.status === "DELIVERED";
  const firstReviewableItem = getFirstReviewableOrderItem({
    status: order.status,
    canReview,
    items: order.items,
  });

  return (
    <div
      // Top padding: safe-area + 16px (pt-4) — defense saat global Header
      // scroll-away di mobile (header non-home tidak sticky), supaya status
      // bar tidak menimpa konten teratas (mis. nomor pesanan, alamat). Di
      // desktop md: layout pakai py-10 default — env() jadi 0 di non-PWA.
      className="min-h-dvh bg-gray-50 [padding-bottom:calc(1.25rem+env(safe-area-inset-bottom))] [padding-top:env(safe-area-inset-top)]"
    >
      <PageStatusBar iconColor="dark" themeColor="#f8fafc" />
      <div className="mx-auto max-w-4xl px-4 pb-24 pt-4 md:py-10">
        {copyMsg && (
          <div className="fixed bottom-24 left-1/2 z-50 -translate-x-1/2 rounded-full bg-gray-950 px-4 py-2 text-xs font-bold text-white shadow-lg md:bottom-6">
            {copyMsg}
          </div>
        )}

        <div className="sticky top-0 z-30 -mx-4 border-b border-gray-100 bg-gray-50/95 px-4 pb-3 pt-3 backdrop-blur md:static md:mx-0 md:border-0 md:bg-transparent md:px-0 md:pb-0 md:pt-0">
          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0">
              <p className="text-xs font-bold uppercase tracking-[0.18em] text-blue-600">
                Pesanan Saya
              </p>
              <h1 className="mt-1 truncate text-xl font-black tracking-tight text-gray-950 md:text-3xl">
                Detail Pesanan
              </h1>
            </div>
            <Link
              href="/member/orders"
              className="shrink-0 rounded-full border border-gray-200 bg-white px-4 py-2 text-xs font-bold text-gray-700 hover:border-blue-300 hover:text-blue-700"
            >
              Pesanan Saya
            </Link>
          </div>
        </div>

        {refreshError && (
          <p className="mt-4 rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-700">
            {refreshError}
          </p>
        )}

        <div className="mt-5 grid gap-5 lg:grid-cols-[1.15fr_0.85fr]">
          <div className="space-y-5">
            <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-widest text-gray-400">
                    Nomor Pesanan
                  </p>
                  <p className="mt-1 text-xl font-black text-gray-950">
                    {order.orderNumber}
                  </p>
                  <p className="mt-1 text-sm text-gray-500">{tanggal}</p>
                </div>
                <button
                  type="button"
                  onClick={() =>
                    copy(order.orderNumber, "Nomor pesanan tersalin")
                  }
                  className="rounded-full bg-blue-50 px-4 py-2 text-xs font-bold text-blue-700 hover:bg-blue-100"
                >
                  Salin Nomor
                </button>
              </div>

              <div className="mt-5 grid gap-3 text-sm text-gray-700">
                <p>
                  <span className="font-semibold">Nama Customer:</span>{" "}
                  {order.customerName}
                </p>
                <p>
                  <span className="font-semibold">Status Pembayaran:</span>{" "}
                  {PAYMENT_STATUS_LABEL[order.paymentStatus] ??
                    order.paymentStatus}
                </p>
                <p>
                  <span className="font-semibold">Metode Pembayaran:</span>{" "}
                  {paymentLabel}
                </p>
              </div>
            </div>

            <StatusTimeline order={order} />

            {order.orderType === "SELF_PICKUP" && (
              <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
                <p className="font-black text-gray-950">Metode Pengambilan</p>
                <div className="mt-3 space-y-3 text-sm text-gray-700">
                  <div>
                    <p className="font-black text-gray-950">Ambil Sendiri di Toko</p>
                    <p className="mt-1 text-xs font-bold text-blue-700">
                      Self Pick Up - Gratis Ongkir
                    </p>
                  </div>
                  <div>
                    <p className="font-semibold text-gray-950">Lokasi Toko</p>
                    <p>{order.pickupStoreName ?? SELF_PICKUP_STORE.name}</p>
                    <p>{order.pickupStoreAddress ?? SELF_PICKUP_STORE.address}</p>
                  </div>
                  <div>
                    <p className="font-semibold text-gray-950">Jam Ambil</p>
                    <p>{order.pickupHours ?? SELF_PICKUP_STORE.hours}</p>
                  </div>
                  {order.status === "READY_FOR_PICKUP" && order.pickupCode && (
                    <div className="rounded-2xl bg-green-50 px-4 py-3 text-center">
                      <p className="text-xs font-bold text-green-700">Kode Pengambilan</p>
                      <p className="mt-1 font-mono text-2xl font-black tracking-widest text-green-800">
                        {order.pickupCode}
                      </p>
                      <p className="mt-1 text-xs text-green-700">
                        Tunjukkan kode ini kepada kasir saat mengambil pesanan.
                      </p>
                    </div>
                  )}
                  <a
                    href={order.pickupMapsUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex w-full justify-center rounded-full border border-blue-200 px-4 py-2.5 text-xs font-black text-blue-700 hover:bg-blue-50"
                  >
                    Buka di Google Maps
                  </a>
                </div>
              </div>
            )}

            <div className={`rounded-3xl border border-gray-100 bg-white p-5 shadow-sm ${
              order.orderType === "SELF_PICKUP" ? "hidden" : ""
            }`}>
              <p className="font-black text-gray-950">Alamat Pengiriman</p>
              <div className="mt-3 space-y-1 text-sm text-gray-700">
                <p>
                  {order.customerName} · {order.customerPhone}
                </p>
                <p>{order.shippingAddress}</p>
                <p>
                  {[order.shippingCity, order.shippingPostalCode]
                    .filter(Boolean)
                    .join(", ") || "-"}
                </p>
                {order.shippingPinpointAddress && (
                  <p className="text-xs text-green-700">
                    Pinpoint: {order.shippingPinpointAddress}
                  </p>
                )}
              </div>
              {(order.courierCode || order.courierService) && (
                <p className="mt-3 text-sm text-gray-700">
                  <span className="font-semibold">Kurir:</span>{" "}
                  {[order.courierCode?.toUpperCase(), order.courierService]
                    .filter(Boolean)
                    .join(" ")}
                </p>
              )}
              <CourierTracking order={order} />
            </div>

            <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
              <div>
                <p className="font-black text-gray-950">Produk</p>
                {showReviewActions && (
                  <p className="mt-1 text-xs text-gray-500">
                    Pesanan selesai. Kamu bisa memberi review untuk produk yang
                    belum diulas.
                  </p>
                )}
              </div>
              <div className="mt-4 space-y-3">
                {order.items.map((item) => (
                  <div
                    key={item.id}
                    className="flex gap-3 rounded-2xl border border-gray-100 bg-white p-3 text-sm"
                  >
                    <Link
                      href={`/products/${item.productSlug}`}
                      aria-label={`Lihat produk ${item.name}`}
                      className="relative h-16 w-16 shrink-0 overflow-hidden rounded-2xl bg-gray-50 ring-1 ring-gray-100"
                    >
                      {item.productImage ? (
                        <Image
                          src={item.productImage}
                          alt={item.name}
                          fill
                          sizes="64px"
                          className="object-cover"
                        />
                      ) : (
                        <span className="grid h-full w-full place-items-center text-gray-400">
                          <FiPackage className="h-6 w-6" aria-hidden />
                        </span>
                      )}
                    </Link>
                    <div className="flex min-w-0 flex-1 items-start justify-between gap-3">
                      <div className="min-w-0">
                        <Link
                          href={`/products/${item.productSlug}`}
                          className="line-clamp-2 font-semibold leading-snug text-gray-800 hover:text-blue-700"
                        >
                          {item.name}
                        </Link>
                        {item.variantLabel && (
                          <p className="mt-1 inline-flex rounded-full bg-blue-50 px-2 py-0.5 text-[11px] font-bold text-blue-700">
                            {item.variantLabel}
                          </p>
                        )}
                        <p className="mt-1 text-xs font-semibold text-gray-500">
                          Qty {item.quantity}
                        </p>
                        <p className="mt-1 font-bold text-gray-900 sm:hidden">
                          {formatRupiah(item.price * item.quantity)}
                        </p>
                      </div>
                      <div className="flex shrink-0 flex-col items-end gap-2">
                        <span className="hidden font-bold text-gray-900 sm:inline">
                          {formatRupiah(item.price * item.quantity)}
                        </span>
                        {showReviewActions &&
                          (item.reviewed ? (
                            <span className="rounded-full bg-green-50 px-3 py-1 text-xs font-bold text-green-700">
                              Sudah direview
                            </span>
                          ) : (
                            <button
                              type="button"
                              onClick={() => setReviewItem(item)}
                              className="rounded-full bg-blue-600 px-4 py-2 text-xs font-black text-white hover:bg-blue-700"
                            >
                              Beri Review
                            </button>
                          ))}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>

          <div className="space-y-5">
            <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
              <p className="font-black text-gray-950">Ringkasan Pembayaran</p>
              <div className="mt-4 space-y-2 text-sm">
                <div className="flex justify-between text-gray-600">
                  <span>Subtotal Produk</span>
                  <span>{formatRupiah(order.subtotal)}</span>
                </div>
                <div className="flex justify-between text-gray-600">
                  <span>Ongkos Kirim</span>
                  <span>{formatRupiah(order.shippingCost)}</span>
                </div>
                {order.discount > 0 && (
                  <div className="flex justify-between text-green-600">
                    <span>Diskon</span>
                    <span>-{formatRupiah(order.discount)}</span>
                  </div>
                )}
                <div className="flex justify-between border-t pt-3 text-base font-black text-gray-950">
                  <span>Total Pembayaran</span>
                  <span>{formatRupiah(order.total)}</span>
                </div>
                {order.paymentProvider === "MANUAL" &&
                  order.uniqueCode !== null && (
                    <div className="flex justify-between text-sm font-bold text-blue-700">
                      <span>Total Transfer</span>
                      <span>{formatRupiah(totalTransfer)}</span>
                    </div>
                  )}
              </div>
            </div>

            {order.paymentProvider === "MANUAL" &&
              bank &&
              order.paymentStatus !== "PAID" && (
                <div className="rounded-3xl border border-blue-100 bg-blue-50 p-5">
                  <p className="font-black text-gray-950">
                    Instruksi Transfer Manual
                  </p>
                  <div className="mt-4 rounded-2xl bg-white p-4">
                    <p className="text-xs text-gray-500">Bank tujuan</p>
                    <p className="mt-1 text-lg font-black text-gray-950">
                      {bank.bankName}
                    </p>
                    <div className="mt-3 flex items-center justify-between gap-3 rounded-xl bg-gray-50 px-3 py-2">
                      <p className="font-mono text-base font-bold tracking-wide text-gray-950">
                        {bank.accountNumber}
                      </p>
                      <button
                        type="button"
                        onClick={() =>
                          copy(bank.accountNumber, "Nomor rekening tersalin")
                        }
                        className="text-xs font-bold text-blue-700 hover:underline"
                      >
                        Salin
                      </button>
                    </div>
                    <p className="mt-1 text-xs text-gray-500">
                      a/n {bank.accountName}
                    </p>
                  </div>
                  <div className="mt-3 rounded-2xl bg-white p-4">
                    <p className="text-xs text-gray-500">
                      Transfer sesuai nominal ini
                    </p>
                    <div className="mt-1 flex items-center justify-between gap-3">
                      <p className="text-2xl font-black text-blue-700">
                        {formatRupiah(totalTransfer)}
                      </p>
                      <button
                        type="button"
                        onClick={() =>
                          copy(String(totalTransfer), "Total transfer tersalin")
                        }
                        className="text-xs font-bold text-blue-700 hover:underline"
                      >
                        Salin
                      </button>
                    </div>
                    {order.uniqueCode !== null && (
                      <p className="mt-2 text-xs text-gray-600">
                        Termasuk kode unik {order.uniqueCode} untuk mempercepat
                        verifikasi.
                      </p>
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
              <a
                href={order.paymentUrl}
                className="inline-flex w-full justify-center rounded-full bg-blue-600 px-5 py-3 text-sm font-black text-white hover:bg-blue-700"
              >
                Bayar Sekarang
              </a>
            )}

            <OrderFollowUpCard
              order={order}
              canReview={canReview}
              reviewableItem={firstReviewableItem}
              onReview={setReviewItem}
            />
          </div>
        </div>
      </div>

      {reviewItem && (
        <ReviewModal
          orderItemId={reviewItem.id}
          productId={reviewItem.productId}
          productName={reviewItem.name}
          productImage={reviewItem.productImage}
          variantLabel={reviewItem.variantLabel}
          onClose={() => setReviewItem(null)}
        />
      )}
    </div>
  );
}
