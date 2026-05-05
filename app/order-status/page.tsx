"use client";

import { useState } from "react";
import { formatRupiah } from "@/lib/format";

type OrderItem = { name: string; quantity: number; price: number };

type Order = {
  orderNumber: string;
  customerName: string;
  customerPhone: string;
  status: string;
  paymentStatus: string;
  paymentProvider: string;
  paymentUrl: string | null;
  subtotal: number;
  shippingCost: number;
  discount: number;
  total: number;
  shippingAddress: string;
  shippingCity: string | null;
  courierCode: string | null;
  courierService: string | null;
  trackingNumber: string | null;
  notes: string | null;
  createdAt: string;
  items: OrderItem[];
};

const STATUS_LABEL: Record<string, string> = {
  PENDING: "Menunggu konfirmasi",
  PAID: "Sudah dibayar",
  PROCESSING: "Sedang dipacking",
  SHIPPED: "Sudah dikirim",
  DELIVERED: "Selesai",
  CANCELLED: "Dibatalkan",
  REFUNDED: "Dikembalikan",
};

const PAYMENT_STATUS_LABEL: Record<string, string> = {
  UNPAID: "Belum bayar",
  PENDING: "Menunggu konfirmasi",
  PAID: "Lunas",
  FAILED: "Gagal",
  EXPIRED: "Kedaluwarsa",
  REFUNDED: "Dikembalikan",
};

export default function OrderStatusPage() {
  const [query, setQuery] = useState("");
  const [order, setOrder] = useState<Order | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    if (!query.trim()) return;
    setError("");
    setOrder(null);
    setLoading(true);

    const res = await fetch(`/api/orders/status?order=${encodeURIComponent(query.trim())}`);
    const data = await res.json();
    setLoading(false);

    if (!res.ok) {
      setError(data.message || "Order tidak ditemukan");
      return;
    }

    setOrder(data);
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-10">
      <h1 className="text-3xl font-black tracking-tight text-zinc-950">Cek Status Pesanan</h1>
      <p className="mt-2 text-zinc-600">Masukkan nomor order untuk melihat status pesanan kamu.</p>

      <form onSubmit={handleSearch} className="mt-8 flex gap-3">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="flex-1 rounded-2xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
          placeholder="Contoh: ORD-20260505-ABC123"
        />
        <button
          type="submit"
          disabled={loading}
          className="rounded-full bg-zinc-950 px-6 py-3 text-sm font-bold text-white disabled:opacity-50"
        >
          {loading ? "Mencari..." : "Cek"}
        </button>
      </form>

      {error && (
        <p className="mt-4 rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-600">{error}</p>
      )}

      {order && <OrderDetail order={order} />}
    </div>
  );
}

function OrderDetail({ order }: { order: Order }) {
  const waNumber = process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ?? "";
  const waText = encodeURIComponent(
    `Halo Natalo Petshop, saya ingin konfirmasi pembayaran order ${order.orderNumber}.`
  );

  return (
    <div className="mt-8 space-y-5">
      <div className="rounded-3xl border border-zinc-200 p-5">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-xs font-semibold uppercase tracking-widest text-zinc-400">Nomor Order</p>
            <p className="mt-1 text-xl font-black text-zinc-950">{order.orderNumber}</p>
          </div>
          <div className="text-right">
            <span className="inline-block rounded-full bg-zinc-100 px-3 py-1 text-xs font-bold text-zinc-700">
              {STATUS_LABEL[order.status] ?? order.status}
            </span>
          </div>
        </div>

        <div className="mt-5 grid gap-2 text-sm text-zinc-700">
          <p><span className="font-semibold">Nama:</span> {order.customerName}</p>
          <p><span className="font-semibold">Alamat:</span> {order.shippingAddress}{order.shippingCity ? `, ${order.shippingCity}` : ""}</p>
          {order.courierCode && (
            <p><span className="font-semibold">Kurir:</span> {order.courierCode.toUpperCase()} {order.courierService ?? ""}</p>
          )}
          {order.trackingNumber && (
            <p><span className="font-semibold">Resi:</span> {order.trackingNumber}</p>
          )}
          {order.notes && (
            <p><span className="font-semibold">Catatan:</span> {order.notes}</p>
          )}
        </div>
      </div>

      <div className="rounded-3xl border border-zinc-200 p-5">
        <p className="font-bold text-zinc-950">Produk</p>
        <div className="mt-4 space-y-2">
          {order.items.map((item, i) => (
            <div key={i} className="flex justify-between text-sm">
              <span>{item.name} × {item.quantity}</span>
              <span>{formatRupiah(item.price * item.quantity)}</span>
            </div>
          ))}
        </div>
        <div className="mt-4 space-y-1 border-t pt-4 text-sm">
          <div className="flex justify-between text-zinc-600">
            <span>Subtotal</span><span>{formatRupiah(order.subtotal)}</span>
          </div>
          <div className="flex justify-between text-zinc-600">
            <span>Ongkir</span><span>{formatRupiah(order.shippingCost)}</span>
          </div>
          {order.discount > 0 && (
            <div className="flex justify-between text-green-600">
              <span>Diskon</span><span>-{formatRupiah(order.discount)}</span>
            </div>
          )}
          <div className="flex justify-between font-black text-zinc-950">
            <span>Total</span><span>{formatRupiah(order.total)}</span>
          </div>
        </div>
      </div>

      <div className="rounded-3xl border border-zinc-200 p-5">
        <p className="font-bold text-zinc-950">Pembayaran</p>
        <p className="mt-2 text-sm text-zinc-700">
          Status:{" "}
          <span className="font-semibold">{PAYMENT_STATUS_LABEL[order.paymentStatus] ?? order.paymentStatus}</span>
        </p>

        {order.paymentStatus !== "PAID" && order.paymentProvider === "MANUAL" && (
          <div className="mt-4 rounded-2xl bg-zinc-50 p-4 text-sm">
            <p className="font-bold text-zinc-950">Instruksi Transfer</p>
            <p className="mt-2">Bank: BCA</p>
            <p>No. Rekening: 8280277046</p>
            <p>Atas Nama: NATASHA</p>
            <p className="mt-2 font-bold text-zinc-950">Total: {formatRupiah(order.total)}</p>

            <a
              href={`https://wa.me/${waNumber.replace("+", "")}?text=${waText}`}
              target="_blank"
              rel="noreferrer"
              className="mt-4 inline-flex w-full justify-center rounded-full bg-zinc-950 px-5 py-3 text-sm font-bold text-white"
            >
              Kirim bukti transfer via WhatsApp
            </a>
          </div>
        )}

        {order.paymentStatus !== "PAID" && order.paymentUrl && (
          <a
            href={order.paymentUrl}
            className="mt-4 inline-flex w-full justify-center rounded-full bg-zinc-950 px-5 py-3 text-sm font-bold text-white"
          >
            Bayar sekarang
          </a>
        )}
      </div>
    </div>
  );
}
