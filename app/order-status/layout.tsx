import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Cek Status Pesanan",
  description: "Masukkan nomor order untuk melihat status pesanan dan informasi pengiriman kamu.",
  robots: { index: false, follow: false },
};

export default function OrderStatusLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}
