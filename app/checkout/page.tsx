"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Script from "next/script";
import { formatRupiah } from "@/lib/format";
import { MetodePengiriman } from "@/components/MetodePengiriman";
import {
  MetodePembayaran,
  type PaymentSelection,
} from "@/components/MetodePembayaran";

type CartItem = {
  productId: string;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
  imageUrl?: string | null;
};

type RateOption = {
  courier_name: string;
  courier_code: string;
  courier_service_name: string;
  courier_service_code: string;
  service_type: string;
  price: number;
  duration: string;
  available: boolean;
  unavailable_reason?: string;
};

declare global {
  interface Window {
    snap?: {
      pay: (token: string, options: {
        onSuccess: (result: unknown) => void;
        onPending: (result: unknown) => void;
        onError: (result: unknown) => void;
        onClose: () => void;
      }) => void;
    };
  }
}

const isMidtransEnabled = !!process.env.NEXT_PUBLIC_MIDTRANS_CLIENT_KEY;

export default function CheckoutPage() {
  const router = useRouter();
  const [items, setItems] = useState<CartItem[]>([]);
  const [rates, setRates] = useState<RateOption[]>([]);
  const [selectedRate, setSelectedRate] = useState<RateOption | null>(null);
  const [shippingSheetOpen, setShippingSheetOpen] = useState(false);
  const [shippingError, setShippingError] = useState("");
  const [payment, setPayment] = useState<PaymentSelection | null>(null);
  const paymentMethod = payment?.provider ?? null;
  const [ratesLoading, setRatesLoading] = useState(false);
  const [orderLoading, setOrderLoading] = useState(false);
  const [error, setError] = useState("");

  const [form, setForm] = useState({
    customerName: "",
    customerPhone: "",
    customerEmail: "",
    shippingAddress: "",
    shippingCity: "",
    shippingPostalCode: "",
    voucherCode: "",
    notes: "",
  });

  type SavedAddress = {
    id: string; label: string; recipientName: string; phone: string;
    address: string; city: string; postalCode: string; isMain: boolean;
    latitude?: number | null; longitude?: number | null; pinpointAddress?: string | null; streetName?: string | null;
  };
  const [savedAddresses, setSavedAddresses] = useState<SavedAddress[]>([]);
  const [selectedAddressId, setSelectedAddressId] = useState<string>("");

  const [voucherInput, setVoucherInput] = useState("");
  const [voucherApplied, setVoucherApplied] = useState<{
    code: string;
    discount: number;
    description: string;
    autoApplied?: boolean;
  } | null>(null);
  const [voucherLoading, setVoucherLoading] = useState(false);
  const [voucherError, setVoucherError] = useState("");
  const [availableVouchers, setAvailableVouchers] = useState<
    Array<{ code: string; description: string | null; discount: number }>
  >([]);
  const [showVoucherList, setShowVoucherList] = useState(false);

  useEffect(() => {
    const raw = localStorage.getItem("cart");
    try {
      const parsed = raw ? JSON.parse(raw) : [];
      setItems(Array.isArray(parsed) ? parsed : []);
    } catch {
      localStorage.removeItem("cart");
      setItems([]);
    }

    fetch("/api/auth/me")
      .then((r) => r.json())
      .then((data) => {
        if (data.name) setForm((f) => ({ ...f, customerName: data.name }));
        if (data.email) setForm((f) => ({ ...f, customerEmail: data.email }));
        if (data.phone) setForm((f) => ({ ...f, customerPhone: data.phone }));
      })
      .catch(() => {});

    fetch("/api/member/addresses")
      .then((r) => r.json())
      .then((addrs) => {
        if (!Array.isArray(addrs) || addrs.length === 0) return;
        setSavedAddresses(addrs);
        const main = addrs.find((a) => a.isMain) ?? addrs[0];
        setSelectedAddressId(main.id);
        applyAddressToForm(main);
      })
      .catch(() => {});
  }, []);

  function applyAddressToForm(addr: { recipientName: string; phone: string; address: string; city: string; postalCode: string }) {
    setForm((f) => ({
      ...f,
      customerName: addr.recipientName || f.customerName,
      customerPhone: addr.phone || f.customerPhone,
      shippingAddress: addr.address,
      shippingCity: addr.city,
      shippingPostalCode: addr.postalCode,
    }));
  }

  const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const shippingCost = selectedRate?.price ?? 0;
  const discount = voucherApplied?.discount ?? 0;
  const total = Math.max(subtotal + shippingCost - discount, 0);

  // ── Auto-apply voucher milik user ──────────────────────────────
  // Fetch user vouchers tiap subtotal berubah. Auto-apply voucher TERBAIK
  // hanya kalau user belum pasang voucher manual.
  useEffect(() => {
    if (subtotal === 0) {
      setAvailableVouchers([]);
      return;
    }

    let cancelled = false;
    fetch(`/api/member/vouchers?subtotal=${subtotal}`)
      .then((r) => (r.ok ? r.json() : { vouchers: [] }))
      .then((data) => {
        if (cancelled) return;
        const list = Array.isArray(data.vouchers) ? data.vouchers : [];
        setAvailableVouchers(list);

        // Auto-apply yang terbaik kalau user belum pakai voucher manual
        if (list.length > 0 && !voucherApplied) {
          const best = list[0];
          setVoucherApplied({
            code: best.code,
            discount: best.discount,
            description: best.description ?? "Voucher otomatis",
            autoApplied: true,
          });
          setForm((f) => ({ ...f, voucherCode: best.code }));
        }

        // Re-validate voucher yang auto-applied (subtotal mungkin berubah)
        if (voucherApplied?.autoApplied) {
          const stillValid = list.find((v: { code: string }) => v.code === voucherApplied.code);
          if (stillValid) {
            // Update discount kalau berbeda
            if (stillValid.discount !== voucherApplied.discount) {
              setVoucherApplied({
                code: stillValid.code,
                discount: stillValid.discount,
                description: stillValid.description ?? "Voucher otomatis",
                autoApplied: true,
              });
            }
          } else {
            // Tidak valid lagi (subtotal turun di bawah minimumOrder, dll) — lepas
            setVoucherApplied(null);
            setForm((f) => ({ ...f, voucherCode: "" }));
          }
        }
      })
      .catch(() => {});

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [subtotal]);

  async function applyVoucher() {
    setVoucherError("");
    if (!voucherInput.trim()) return;
    setVoucherLoading(true);
    const res = await fetch("/api/vouchers/validate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code: voucherInput.trim().toUpperCase(), subtotal }),
    });
    const data = await res.json();
    setVoucherLoading(false);
    if (data.valid) {
      setVoucherApplied({ code: data.code, discount: data.discount, description: data.description });
      setForm((f) => ({ ...f, voucherCode: data.code }));
    } else {
      setVoucherError(data.error || "Kode voucher tidak valid.");
    }
  }

  function removeVoucher() {
    setVoucherApplied(null);
    setVoucherInput("");
    setVoucherError("");
    setForm((f) => ({ ...f, voucherCode: "" }));
  }

  async function getRates() {
    if (!form.shippingPostalCode) {
      setShippingError("Isi kode pos dulu untuk cek ongkir.");
      return;
    }
    if (items.length === 0) {
      setShippingError("Keranjang kosong.");
      return;
    }
    setShippingError("");
    setRatesLoading(true);
    setShippingSheetOpen(true);

    try {
      // Format items per spec Biteship: per item dengan name, value, weight, quantity
      const biteshipItems = items.map((it) => ({
        name: it.name,
        price: it.price,
        weightGram: it.weightGram,
        quantity: it.quantity,
      }));

      const res = await fetch("/api/shipping/rates", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          destinationPostalCode: form.shippingPostalCode,
          items: biteshipItems,
        }),
      });
      const data = await res.json();

      if (!res.ok) {
        setShippingError(data.message ?? "Gagal memuat ongkir, coba lagi.");
        setRates([]);
      } else {
        setRates(data.rates || []);
      }
    } catch {
      setShippingError("Gagal memuat ongkir, coba lagi.");
      setRates([]);
    } finally {
      setRatesLoading(false);
    }
  }

  function clearCart() {
    localStorage.removeItem("cart");
    window.dispatchEvent(new Event("cart-updated"));
    setItems([]);
  }

  async function handleOrder(e: React.FormEvent) {
    e.preventDefault();
    setError("");

    if (items.length === 0) {
      setError("Keranjang kosong.");
      return;
    }

    if (!selectedRate) {
      setError("Pilih kurir pengiriman terlebih dahulu. Klik \"Cek Ongkir\" dan pilih salah satu layanan.");
      return;
    }

    if (!payment) {
      setError("Pilih metode pembayaran terlebih dahulu.");
      return;
    }

    setOrderLoading(true);
    const res = await fetch("/api/orders", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ...form,
        paymentProvider: payment.provider,
        manualBank: payment.provider === "MANUAL" ? payment.bank : undefined,
        items,
        shippingCost,
        courierCode: selectedRate?.courier_code,
        courierService: selectedRate?.courier_service_code,
      }),
    });

    const data = await res.json();
    setOrderLoading(false);

    if (!res.ok) {
      setError(data.message || "Gagal membuat order.");
      return;
    }

    if (paymentMethod === "MIDTRANS" && data.snapToken && window.snap) {
      window.snap.pay(data.snapToken, {
        onSuccess: () => {
          clearCart();
          router.push(`/order-status?order=${data.orderNumber}`);
        },
        onPending: () => {
          clearCart();
          router.push(`/order-status?order=${data.orderNumber}`);
        },
        onError: () => {
          setError("Pembayaran gagal. Silakan coba lagi.");
        },
        onClose: () => {
          setError("Pembayaran dibatalkan. Order tetap tersimpan, buka kembali melalui cek status order.");
          clearCart();
          router.push(`/order-status?order=${data.orderNumber}`);
        },
      });
      return;
    }

    clearCart();
    router.push(`/order-status?order=${data.orderNumber}`);
  }

  function field(
    label: string,
    key: keyof typeof form,
    opts?: { required?: boolean; type?: string; placeholder?: string; textarea?: boolean }
  ) {
    const cls =
      "mt-1 block w-full rounded-2xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600";
    return (
      <div>
        <label className="block text-sm font-medium text-zinc-700">
          {label}
          {opts?.required && <span className="ml-1 text-red-500">*</span>}
        </label>
        {opts?.textarea ? (
          <textarea
            rows={3}
            required={opts.required}
            placeholder={opts.placeholder}
            value={form[key]}
            onChange={(e) => setForm({ ...form, [key]: e.target.value })}
            className={cls}
          />
        ) : (
          <input
            type={opts?.type ?? "text"}
            required={opts?.required}
            placeholder={opts?.placeholder}
            value={form[key]}
            onChange={(e) => setForm({ ...form, [key]: e.target.value })}
            className={cls}
          />
        )}
      </div>
    );
  }

  const isProduction = process.env.NEXT_PUBLIC_MIDTRANS_IS_PRODUCTION === "true";
  const snapScriptUrl = isProduction
    ? "https://app.midtrans.com/snap/snap.js"
    : "https://app.sandbox.midtrans.com/snap/snap.js";

  return (
    <>
      {isMidtransEnabled && (
        <Script
          src={snapScriptUrl}
          data-client-key={process.env.NEXT_PUBLIC_MIDTRANS_CLIENT_KEY}
          strategy="lazyOnload"
        />
      )}

      <div className="mx-auto grid max-w-6xl gap-8 px-4 py-4 pb-32 lg:grid-cols-[1fr_360px] lg:py-10 lg:pb-10">
        <div>
          <h1 className="text-2xl font-black tracking-tight text-zinc-950 lg:text-3xl">Checkout</h1>

          {/* Mobile-only: ringkasan mini di atas form */}
          {items.length > 0 && (
            <div className="mt-4 rounded-2xl bg-zinc-50 px-4 py-3 lg:hidden">
              <div className="flex items-center justify-between text-sm">
                <span className="text-zinc-500">{items.reduce((s, i) => s + i.quantity, 0)} item</span>
                <span className="font-black text-zinc-950">
                  {selectedRate ? `Total: Rp ${(total).toLocaleString("id-ID")}` : `Subtotal: Rp ${subtotal.toLocaleString("id-ID")}`}
                </span>
              </div>
            </div>
          )}

          <form id="checkout-form" onSubmit={handleOrder} className="mt-8 space-y-4">
            {/* Pilih alamat tersimpan */}
            {savedAddresses.length > 0 && (
              <div>
                <p className="text-sm font-medium text-zinc-700">Alamat tersimpan</p>
                <div className="mt-2 space-y-2">
                  {savedAddresses.map((addr) => (
                    <button
                      key={addr.id}
                      type="button"
                      onClick={() => {
                        setSelectedAddressId(addr.id);
                        applyAddressToForm(addr);
                      }}
                      className={`w-full rounded-2xl border p-4 text-left text-sm transition ${
                        selectedAddressId === addr.id
                          ? "border-zinc-950 bg-zinc-50"
                          : "border-zinc-200 hover:border-zinc-400"
                      }`}
                    >
                      <div className="flex items-center justify-between gap-2">
                        <span className="font-bold text-zinc-900">{addr.label}</span>
                        {addr.isMain && (
                          <span className="rounded-full bg-natalo-100 px-2 py-0.5 text-xs font-bold text-natalo-700">
                            Utama
                          </span>
                        )}
                        {selectedAddressId === addr.id && (
                          <span className="text-xs font-bold text-zinc-500">✓ Dipilih</span>
                        )}
                      </div>
                      <p className="mt-1 text-zinc-600">{addr.recipientName} · {addr.phone}</p>
                      <p className="mt-0.5 text-zinc-400 line-clamp-1">{addr.address}, {addr.city} {addr.postalCode}</p>
                      {addr.streetName && (
                        <p className="mt-2 text-xs font-bold text-natalo-700">{addr.streetName}</p>
                      )}
                      {addr.pinpointAddress && (
                        <p className="mt-2 rounded-xl bg-natalo-50 px-3 py-2 text-xs font-semibold text-natalo-800 line-clamp-2">
                          Pinpoint: {addr.pinpointAddress}
                        </p>
                      )}
                    </button>
                  ))}
                </div>
                <p className="mt-2 text-xs text-zinc-400">
                  Atau isi form di bawah secara manual untuk alamat berbeda.
                </p>
              </div>
            )}

            {field("Nama lengkap", "customerName", { required: true, placeholder: "Nama penerima" })}
            {field("Nomor WhatsApp", "customerPhone", { required: true, type: "tel", placeholder: "08123..." })}
            {field("Email", "customerEmail", { type: "email", placeholder: "Opsional" })}
            {field("Alamat lengkap", "shippingAddress", {
              required: true,
              placeholder: "Jalan, RT/RW, Kelurahan, Kecamatan...",
              textarea: true,
            })}

            <div className="grid gap-4 sm:grid-cols-2">
              {field("Kota / Kecamatan", "shippingCity", { placeholder: "Contoh: Jakarta Selatan" })}
              {field("Kode pos", "shippingPostalCode", { type: "tel", placeholder: "12345" })}
            </div>

            {/* Pengiriman: tombol → bottom sheet */}
            <div>
              <label className="block text-sm font-medium text-zinc-700">
                Metode Pengiriman
              </label>
              {selectedRate ? (
                <div className="mt-1 flex items-center justify-between gap-3 rounded-2xl border border-natalo-300 bg-natalo-50 p-4">
                  <div className="min-w-0">
                    <p className="font-bold text-zinc-950">
                      🚚 {selectedRate.courier_name}{" "}
                      <span className="text-sm font-normal text-zinc-600">
                        — {selectedRate.courier_service_name}
                      </span>
                    </p>
                    <p className="mt-0.5 text-xs text-zinc-500">
                      {selectedRate.duration} · {formatRupiah(selectedRate.price)}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={getRates}
                    className="shrink-0 text-xs font-bold text-natalo-700 hover:underline"
                  >
                    Ganti
                  </button>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={getRates}
                  disabled={ratesLoading || !form.shippingPostalCode}
                  className="mt-1 flex w-full items-center justify-between rounded-2xl border border-zinc-300 bg-white p-4 text-left transition hover:border-natalo-300 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <span className="font-medium text-zinc-700">
                    {ratesLoading
                      ? "🔄 Memuat ongkir..."
                      : !form.shippingPostalCode
                      ? "Isi kode pos dulu untuk cek ongkir"
                      : "🚚 Pilih metode pengiriman →"}
                  </span>
                  {!ratesLoading && form.shippingPostalCode && (
                    <span className="text-zinc-400">›</span>
                  )}
                </button>
              )}
              {shippingError && (
                <p className="mt-2 text-xs text-red-500">{shippingError}</p>
              )}
            </div>

            {/* Voucher */}
            <div>
              <div className="flex items-center justify-between">
                <label className="block text-sm font-medium text-zinc-700">Kode voucher</label>
                {availableVouchers.length > 0 && (
                  <button
                    type="button"
                    onClick={() => setShowVoucherList((v) => !v)}
                    className="text-xs font-bold text-natalo-600 hover:underline"
                  >
                    {showVoucherList ? "Tutup" : `🎟️ Voucher saya (${availableVouchers.length})`}
                  </button>
                )}
              </div>

              {voucherApplied ? (
                <div className="mt-1 rounded-2xl border border-green-300 bg-green-50 px-4 py-3">
                  <div className="flex items-center justify-between gap-3">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <p className="truncate text-sm font-bold text-green-700">
                          ✅ {voucherApplied.code}
                        </p>
                        {voucherApplied.autoApplied && (
                          <span className="shrink-0 rounded-full bg-natalo-100 px-2 py-0.5 text-[10px] font-bold text-natalo-800">
                            ⚡ Otomatis
                          </span>
                        )}
                      </div>
                      <p className="mt-0.5 text-xs text-green-600">
                        {voucherApplied.description} — hemat{" "}
                        {formatRupiah(voucherApplied.discount)}
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={removeVoucher}
                      className="shrink-0 text-xs font-semibold text-zinc-500 hover:text-red-500"
                    >
                      {voucherApplied.autoApplied ? "Ganti" : "Hapus"}
                    </button>
                  </div>
                </div>
              ) : (
                <div className="mt-1 flex gap-2">
                  <input
                    type="text"
                    value={voucherInput}
                    onChange={(e) => setVoucherInput(e.target.value.toUpperCase())}
                    placeholder="Contoh: LEBARAN20 atau POIN-XXXX"
                    className="block flex-1 rounded-2xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
                    onKeyDown={(e) =>
                      e.key === "Enter" && (e.preventDefault(), applyVoucher())
                    }
                  />
                  <button
                    type="button"
                    onClick={applyVoucher}
                    disabled={voucherLoading || !voucherInput.trim()}
                    className="rounded-2xl bg-zinc-950 px-5 py-3 text-sm font-bold text-white disabled:opacity-40"
                  >
                    {voucherLoading ? "..." : "Terapkan"}
                  </button>
                </div>
              )}

              {/* Daftar voucher milik user */}
              {showVoucherList && availableVouchers.length > 0 && (
                <div className="mt-2 space-y-1.5 rounded-2xl border border-zinc-200 bg-zinc-50 p-2">
                  {availableVouchers.map((v) => {
                    const isCurrent = voucherApplied?.code === v.code;
                    return (
                      <button
                        key={v.code}
                        type="button"
                        disabled={isCurrent}
                        onClick={() => {
                          setVoucherApplied({
                            code: v.code,
                            discount: v.discount,
                            description: v.description ?? "Voucher",
                            autoApplied: false,
                          });
                          setForm((f) => ({ ...f, voucherCode: v.code }));
                          setShowVoucherList(false);
                        }}
                        className={`flex w-full items-center justify-between gap-3 rounded-xl border p-3 text-left transition ${
                          isCurrent
                            ? "border-green-300 bg-green-50"
                            : "border-zinc-200 bg-white hover:border-natalo-300 hover:bg-natalo-50"
                        }`}
                      >
                        <div className="min-w-0 flex-1">
                          <p className="truncate font-mono text-sm font-bold text-zinc-950">
                            {v.code}
                          </p>
                          <p className="truncate text-xs text-zinc-500">
                            {v.description}
                          </p>
                        </div>
                        <div className="shrink-0 text-right">
                          <p className="text-sm font-bold text-natalo-600">
                            -{formatRupiah(v.discount)}
                          </p>
                          {isCurrent && (
                            <p className="text-[10px] font-bold text-green-600">✓ Dipakai</p>
                          )}
                        </div>
                      </button>
                    );
                  })}
                </div>
              )}

              {voucherError && <p className="mt-1 text-xs text-red-500">{voucherError}</p>}
            </div>

            {field("Catatan pesanan", "notes", { placeholder: "Opsional", textarea: true })}

            {/* Metode pembayaran */}
            <div>
              <p className="text-sm font-medium text-zinc-700">Metode pembayaran</p>
              <div className="mt-2 space-y-2">
                <button
                  type="button"
                  onClick={() => setPayment({ provider: "MANUAL", bank: "BCA_NATASHA" })}
                  className={`w-full rounded-2xl border p-4 text-left text-sm transition ${
                    paymentMethod === "MANUAL" ? "border-zinc-950 bg-zinc-50" : "border-zinc-200"
                  }`}
                >
                  <p className="font-semibold">Transfer Manual</p>
                  <p className="text-zinc-500">BCA · No. rek & instruksi tampil setelah order dibuat</p>
                </button>

                {isMidtransEnabled && (
                  <button
                    type="button"
                    onClick={() => setPayment({ provider: "MIDTRANS" })}
                    className={`w-full rounded-2xl border p-4 text-left text-sm transition ${
                      paymentMethod === "MIDTRANS" ? "border-zinc-950 bg-zinc-50" : "border-zinc-200"
                    }`}
                  >
                    <p className="font-semibold">Midtrans</p>
                    <p className="text-zinc-500">Transfer bank, QRIS, GoPay, OVO, dan lainnya</p>
                  </button>
                )}
              </div>
            </div>
          </form>
        </div>

        <aside className="h-fit rounded-3xl bg-zinc-50 p-5">
          <p className="font-bold text-zinc-950">Ringkasan</p>

          <div className="mt-4 space-y-2 text-sm">
            {items.length > 0 ? (
              items.map((item) => (
                <div key={item.productId} className="flex items-center justify-between gap-3">
                  <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded-xl bg-zinc-100">
                    {item.imageUrl ? (
                      <Image
                        src={item.imageUrl}
                        alt={item.name}
                        fill
                        sizes="48px"
                        className="object-cover"
                      />
                    ) : (
                      <div className="flex h-full items-center justify-center text-xl">ðŸ¾</div>
                    )}
                  </div>
                  <span className="text-zinc-700">
                    {item.name} × {item.quantity}
                  </span>
                  <span>{formatRupiah(item.price * item.quantity)}</span>
                </div>
              ))
            ) : (
              <p className="text-zinc-500">Keranjang kosong.</p>
            )}
          </div>

          <div className="mt-5 space-y-2 border-t pt-4 text-sm">
            <div className="flex justify-between text-zinc-600">
              <span>Subtotal</span>
              <span>{formatRupiah(subtotal)}</span>
            </div>
            <div className="flex justify-between text-zinc-600">
              <span>Ongkir</span>
              {selectedRate ? (
                <span>{formatRupiah(shippingCost)}</span>
              ) : (
                <span className="italic text-zinc-400">Belum dipilih</span>
              )}
            </div>
            {voucherApplied && (
              <div className="flex justify-between font-semibold text-green-600">
                <span>Diskon voucher</span>
                <span>-{formatRupiah(discount)}</span>
              </div>
            )}
            <div className="flex justify-between text-lg font-black text-zinc-950">
              <span>Total</span>
              <span>{selectedRate ? formatRupiah(total) : formatRupiah(subtotal) + " + ongkir"}</span>
            </div>
          </div>

          {error && (
            <p className="mt-4 rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-600">{error}</p>
          )}

          <button
            type="submit"
            form="checkout-form"
            disabled={orderLoading || items.length === 0}
            className="mt-5 w-full rounded-full bg-zinc-950 px-6 py-4 text-sm font-bold text-white disabled:opacity-50"
          >
            {orderLoading
              ? "Memproses..."
              : paymentMethod === "MIDTRANS"
              ? "Bayar dengan Midtrans"
              : "Buat Order"}
          </button>

          {paymentMethod === "MANUAL" && (
            <p className="mt-3 text-center text-xs text-zinc-400">
              Instruksi transfer akan tampil setelah order dibuat.
            </p>
          )}
        </aside>
      </div>

      {/* Bottom sheet pilih pengiriman */}
      <MetodePengiriman
        open={shippingSheetOpen}
        onClose={() => setShippingSheetOpen(false)}
        rates={rates}
        loading={ratesLoading}
        error={shippingError || undefined}
        selected={selectedRate}
        onSelect={(r) => setSelectedRate(r as RateOption)}
      />

      {/* Mobile sticky bottom CTA */}
      {items.length > 0 && (
        <div className="fixed inset-x-0 bottom-[70px] z-40 border-t border-zinc-200 bg-white px-4 py-3 shadow-[0_-4px_12px_rgba(0,0,0,0.06)] md:hidden [padding-bottom:calc(12px+env(safe-area-inset-bottom))]">
          <div className="flex items-center gap-3">
            <div className="min-w-0 flex-1">
              <p className="text-xs text-zinc-500">
                {selectedRate ? "Total" : "Subtotal"}
              </p>
              <p className="truncate text-base font-black text-zinc-950">
                {selectedRate ? formatRupiah(total) : `${formatRupiah(subtotal)} + ongkir`}
              </p>
            </div>
            <button
              type="submit"
              form="checkout-form"
              disabled={orderLoading || items.length === 0}
              className="flex h-12 shrink-0 items-center justify-center rounded-full bg-zinc-950 px-6 text-sm font-bold text-white disabled:opacity-50"
            >
              {orderLoading
                ? "Memproses..."
                : paymentMethod === "MIDTRANS"
                  ? "Bayar"
                  : "Buat Order"}
            </button>
          </div>
        </div>
      )}
    </>
  );
}
