import type { Metadata } from "next";
import { NotificationsList } from "@/components/NotificationsList";
import { StickyBackTitle } from "@/components/StickyBackTitle";

export const metadata: Metadata = {
  title: "Notifikasi",
  // Halaman personalized — jangan di-index search engine.
  robots: { index: false, follow: false },
};

export default function NotificationsPage() {
  return (
    <div className="min-h-screen bg-slate-50">
      <StickyBackTitle label="Notifikasi" fallbackHref="/" />
      <div className="mx-auto w-full max-w-2xl px-4 py-6 sm:py-8">
        <div className="rounded-3xl border border-slate-100 bg-white p-4 shadow-sm sm:p-5">
          <NotificationsList />
        </div>
      </div>
    </div>
  );
}
