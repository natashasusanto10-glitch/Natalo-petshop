"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Script from "next/script";
import { formatRupiah } from "@/lib/format";

type CartItem = {
  productId: string;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
};

type RateOption = {
  courier_name: string;
  courier_code: string;
  courier_service_name: string;
  courier_service_code: string;
  price: number;
  duration?: string;
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
  const [paymentMethod, setPaymentMethod] = useState<"MANUAL" | "MIDTRANS">("MANUAL");
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

  useEffect(() => {
    const raw = localStorage.getItem("cart");
    setItems(raw ? JSON.parse(raw) : []);

    fetch("/api/auth/me")
      .then((r) => r.json())
      .then((data) => {
        if (data.name) setForm((f) => ({ ...f, customerName: data.name }));
        if (data.email) setForm((f) => ({ ...f, customerEmail: data.email }));
        if (data.phone) setForm((f) => ({ ...f, customerPhone: data.phone }));
      })
      .catch(() => {});
  }, []);

  const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const shippingCost = selectedRate?.price ?? 0;
  const total = subtotal + shippingCost;

  async function getRates() {
    if (!form.shippingPostalCode) {
      setError("Isi kode pos dulu untuk cek ongkir.");
      return;
    }
    setError("");
    setRatesLoading(true);
    const res = await fetch("/api/shipping/rates", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ destinationPostalCode: form.shippingPostalCode, items }),
    });
    const data = await res.json();
    setRates(data.rates || []);
    setRatesLoading(false);
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

    setOrderLoading(true);
    const res = await fetch("/api/orders", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ...form,
        paymentProvider: paymentMethod,
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

      <div className="mx-auto grid max-w-6xl gap-8 px-4 py-6 lg:grid-cols-[1fr_360px] lg:py-10">
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
            {field("Nama lengkap", "customerName", { required: true, placeholder: "Nama penerima" })}
            {field("Nomor WhatsApp", "customerPhone", { required: true, placeholder: "08123..." })}
            {field("Email", "customerEmail", { type: "email", placeholder: "Opsional" })}
            {field("Alamat lengkap", "shippingAddress", {
              required: true,
              placeholder: "Jalan, RT/RW, Kelurahan, Kecamatan...",
              textarea: true,
            })}

            <div className="grid gap-4 sm:grid-cols-2">
              {field("Kota / Kecamatan", "shippingCity", { placeholder: "Contoh: Jakarta Selatan" })}
              {field("Kode pos", "shippingPostalCode", { placeholder: "12345" })}
            </div>

            <button
              type="button"
              onClick={getRates}
              disabled={ratesLoading}
              className="rounded-full border border-zinc-300 px-5 py-3 text-sm font-bold disabled:opacity-50"
            >
              {ratesLoading ? "Mengecek..." : "Cek Ongkir"}
            </button>

            {rates.length > 0 && (
              <div className="space-y-2">
                <p className="text-sm font-medium text-zinc-700">Pilih kurir</p>
                {rates.map((rate, i) => (
                  <button
                    key={i}
                    type="button"
                    onClick={() => setSelectedRate(rate)}
                    className={`w-full rounded-2xl border p-4 text-left text-sm transition ${
                      selectedRate === rate ? "border-zinc-950 bg-zinc-50" : "border-zinc-200"
                    }`}
                  >
                    <p className="font-semibold">
                      {rate.courier_name} — {rate.courier_service_name}
                    </p>
                    <p className="text-zinc-500">
                      {formatRupiah(rate.price)}
                      {rate.duration ? ` • ${rate.duration}` : ""}
                    </p>
                  </button>
                ))}
              </div>
            )}

            {field("Kode voucher", "voucherCode", { placeholder: "Opsional, contoh: MEMBER10" })}
            {field("Catatan pesanan", "notes", { placeholder: "Opsional", textarea: true })}

            {/* Metode pembayaran */}
            <div>
              <p className="text-sm font-medium text-zinc-700">Metode pembayaran</p>
              <div className="mt-2 space-y-2">
                <button
                  type="button"
                  onClick={() => setPaymentMethod("MANUAL")}
                  className={`w-full rounded-2xl border p-4 text-left text-sm transition ${
                    paymentMethod === "MANUAL" ? "border-zinc-950 bg-zinc-50" : "border-zinc-200"
                  }`}
                >
                  <p className="font-semibold">Transfer Manual</p>
                  <p className="text-zinc-500">BCA · Konfirmasi via WhatsApp</p>
                </button>

                {isMidtransEnabled && (
                  <button
                    type="button"
                    onClick={() => setPaymentMethod("MIDTRANS")}
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
                <div key={item.productId} className="flex justify-between gap-3">
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
              <span>{selectedRate ? formatRupiah(shippingCost) : "—"}</span>
            </div>
            <div className="flex justify-between text-lg font-black text-zinc-950">
              <span>Total</span>
              <span>{formatRupiah(total)}</span>
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
    </>
  );
}
