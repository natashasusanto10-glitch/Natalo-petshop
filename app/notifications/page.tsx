import type { Metadata } from "next";
import { NotificationsList } from "@/components/NotificationsList";

export const metadata: Metadata = {
  title: "Notifikasi",
  // Halaman personalized — jangan di-index search engine.
  robots: { index: false, follow: false },
};

export default function NotificationsPage() {
  return (
    <div className="mx-auto w-full max-w-2xl px-4 py-6 sm:py-10">
      <h1 className="text-2xl font-black text-zinc-900">Notifikasi</h1>
      <p className="mt-1 text-sm text-zinc-500">
        Update pesanan, promo, dan pengumuman dari Natalo Petshop.
      </p>
      <div className="mt-6">
        <NotificationsList />
      </div>
    </div>
  );
}
