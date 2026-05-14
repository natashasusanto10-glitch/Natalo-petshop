"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";

type Props = {
  initialOrderNumber?: string;
};

const WA_NUMBER =
  process.env.NEXT_PUBLIC_WA_NUMBER ||
  process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ||
  "";
const WA_HREF = WA_NUMBER
  ? `https://wa.me/${WA_NUMBER.replace("+", "")}`
  : "";

const API_FAIL_MESSAGE =
  "Form belum bisa dimuat. Coba lagi atau hubungi admin WhatsApp.";

export function OrderStatusClient({ initialOrderNumber = "" }: Props) {
  const router = useRouter();
  // Initial value langsung dari prop SSR — tidak perlu useEffect/
  // useSearchParams. Form input live sejak first render.
  const [orderNumber, setOrderNumber] = useState(initialOrderNumber);
  const [contact, setContact] = useState("");
  const [error, setError] = useState("");
  // `apiFail` ditandai saat fetch throws (network down / CORS / 5xx tanpa
  // body JSON) — beda dari validation error biasa supaya kita bisa kasih
  // CTA WhatsApp ke admin.
  const [apiFail, setApiFail] = useState(false);
  const [loading, setLoading] = useState(false);
  // AbortController untuk cancel in-flight fetch saat unmount/resubmit.
  // Tanpa ini, response slow lama bisa overwrite state setelah user
  // navigate / submit ulang dgn data baru.
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    return () => {
      abortRef.current?.abort();
    };
  }, []);

  async function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    if (!orderNumber.trim() || !contact.trim()) return;
    setError("");
    setApiFail(false);
    setLoading(true);

    // Abort previous request kalau ada (user re-submit cepat)
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    const params = new URLSearchParams({
      order: orderNumber.trim(),
      contact: contact.trim(),
    });

    try {
      const res = await fetch(`/api/orders/status?${params}`, {
        signal: controller.signal,
      });
      let data: { message?: string; detailUrl?: string } = {};
      try {
        data = await res.json();
      } catch {
        // Response bukan JSON valid → treat as API failure
        setApiFail(true);
        return;
      }

      if (!res.ok) {
        setError(data.message || "Pesanan tidak ditemukan.");
        return;
      }

      if (!data.detailUrl) {
        setApiFail(true);
        return;
      }

      router.push(data.detailUrl);
    } catch (err) {
      // AbortError = user re-submit / unmount, jangan show error
      if (err instanceof Error && err.name === "AbortError") return;
      // Network error, offline, fetch aborted, etc.
      setApiFail(true);
    } finally {
      // Hanya unset loading kalau controller ini masih yang aktif
      if (abortRef.current === controller) setLoading(false);
    }
  }

  return (
    <div className="mx-auto max-w-2xl px-4 py-8 md:py-14">
      <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm md:p-8">
        <p className="text-xs font-bold uppercase tracking-[0.2em] text-blue-600">
          Fallback Tracking
        </p>
        <h1 className="mt-2 text-2xl font-black tracking-tight text-gray-950 md:text-3xl">
          Cek Status Pesanan
        </h1>
        <p className="mt-2 text-sm leading-6 text-gray-600">
          Gunakan halaman ini kalau kamu kehilangan link detail pesanan.
          Setelah data cocok, kamu akan diarahkan ke halaman detail pesanan.
        </p>

        <form onSubmit={handleSearch} className="mt-7 space-y-4">
          <div>
            <label htmlFor="order-number" className="text-sm font-bold text-gray-800">
              Nomor Pesanan
            </label>
            <input
              id="order-number"
              name="order"
              value={orderNumber}
              onChange={(e) => setOrderNumber(e.target.value)}
              required
              autoComplete="off"
              className="mt-1 w-full rounded-2xl border border-gray-300 px-4 py-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
              placeholder="Contoh: ORD-20260505-ABC123"
            />
          </div>
          <div>
            <label htmlFor="order-contact" className="text-sm font-bold text-gray-800">
              Email / No. HP Checkout
            </label>
            <input
              id="order-contact"
              name="contact"
              value={contact}
              onChange={(e) => setContact(e.target.value)}
              required
              autoComplete="email"
              className="mt-1 w-full rounded-2xl border border-gray-300 px-4 py-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
              placeholder="email@kamu.com atau 08123..."
            />
          </div>
          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-full bg-blue-600 px-6 py-3 text-sm font-black text-white transition hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-gray-300"
          >
            {loading ? "Memeriksa..." : "Lihat Detail Pesanan"}
          </button>
        </form>

        {apiFail && (
          <div
            role="alert"
            className="mt-4 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
          >
            <p className="font-bold">{API_FAIL_MESSAGE}</p>
            {WA_HREF && (
              <a
                href={WA_HREF}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-2 inline-flex items-center gap-1 font-bold text-amber-900 underline"
              >
                Chat Admin WhatsApp
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} className="h-4 w-4">
                  <path d="M7 17 17 7M9 7h8v8" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </a>
            )}
          </div>
        )}

        {error && !apiFail && (
          <p className="mt-4 rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-600">
            {error}
          </p>
        )}
      </div>
    </div>
  );
}
