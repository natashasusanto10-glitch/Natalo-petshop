import type { Metadata } from "next";
import { OrderStatusClient } from "./OrderStatusClient";

export const metadata: Metadata = {
  title: "Cek Status Pesanan",
  description:
    "Masukkan nomor order untuk melihat status pesanan dan informasi pengiriman kamu.",
  robots: { index: false, follow: false },
};

type PageProps = {
  searchParams: Promise<{ order?: string }>;
};

/**
 * Server component — render shell + form layout langsung pada SSR/initial
 * render. Tidak ada `useSearchParams()` di anak client (initial value
 * di-passing lewat props), jadi tidak perlu Suspense boundary. User tidak
 * pernah melihat "Memuat form cek status..." flash; form input sudah live
 * sejak first paint.
 */
export default async function OrderStatusPage({ searchParams }: PageProps) {
  const { order = "" } = await searchParams;
  return <OrderStatusClient initialOrderNumber={order} />;
}
