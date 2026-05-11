import type { Metadata } from "next";
import { Suspense } from "react";
import { OrderStatusClient } from "./OrderStatusClient";

export const metadata: Metadata = {
  title: "Cek Status Pesanan",
  description: "Masukkan nomor order untuk melihat status pesanan dan informasi pengiriman kamu.",
  robots: { index: false, follow: false },
};

export default function OrderStatusPage() {
  return (
    <Suspense fallback={<div className="mx-auto max-w-2xl px-4 py-8 text-sm text-gray-500">Memuat form cek status...</div>}>
      <OrderStatusClient />
    </Suspense>
  );
}
