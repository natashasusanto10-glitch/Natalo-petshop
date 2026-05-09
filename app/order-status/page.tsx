"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

function OrderStatusForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [orderNumber, setOrderNumber] = useState("");
  const [contact, setContact] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    setOrderNumber(searchParams.get("order") ?? "");
  }, [searchParams]);

  async function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    if (!orderNumber.trim() || !contact.trim()) return;
    setError("");
    setLoading(true);

    const params = new URLSearchParams({
      order: orderNumber.trim(),
      contact: contact.trim(),
    });
    const res = await fetch(`/api/orders/status?${params}`);
    const data = await res.json();
    setLoading(false);

    if (!res.ok) {
      setError(data.message || "Pesanan tidak ditemukan.");
      return;
    }

    router.push(data.detailUrl);
  }

  return (
    <div className="mx-auto max-w-2xl px-4 py-8 md:py-14">
      <div className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm md:p-8">
        <p className="text-xs font-bold uppercase tracking-[0.2em] text-blue-600">Fallback Tracking</p>
        <h1 className="mt-2 text-2xl font-black tracking-tight text-gray-950 md:text-3xl">Cek Status Pesanan</h1>
        <p className="mt-2 text-sm leading-6 text-gray-600">
          Gunakan halaman ini kalau kamu kehilangan link detail pesanan. Setelah data cocok, kamu akan diarahkan ke halaman detail pesanan.
        </p>

        <form onSubmit={handleSearch} className="mt-7 space-y-4">
          <div>
            <label className="text-sm font-bold text-gray-800">Nomor Pesanan</label>
            <input
              value={orderNumber}
              onChange={(e) => setOrderNumber(e.target.value)}
              required
              className="mt-1 w-full rounded-2xl border border-gray-300 px-4 py-3 text-sm outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
              placeholder="Contoh: ORD-20260505-ABC123"
            />
          </div>
          <div>
            <label className="text-sm font-bold text-gray-800">Email / No. HP Checkout</label>
            <input
              value={contact}
              onChange={(e) => setContact(e.target.value)}
              required
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

        {error && (
          <p className="mt-4 rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-600">{error}</p>
        )}
      </div>
    </div>
  );
}

export default function OrderStatusPage() {
  return (
    <Suspense fallback={<div className="mx-auto max-w-2xl px-4 py-8 text-sm text-gray-500">Memuat form cek status...</div>}>
      <OrderStatusForm />
    </Suspense>
  );
}
