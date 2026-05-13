import type { Metadata } from "next";
import { NotificationPreferences } from "@/components/NotificationPreferences";

export const metadata: Metadata = {
  title: "Pengaturan Notifikasi",
  robots: { index: false, follow: false },
};

export default function NotificationsPage() {
  return (
    <main className="mx-auto w-full max-w-2xl px-4 py-6 pb-[calc(6rem+env(safe-area-inset-bottom))] sm:py-10">
      <p className="text-xs font-black uppercase tracking-[0.18em] text-blue-600">
        Pengaturan
      </p>
      <h1 className="mt-1 text-2xl font-black text-zinc-950">Notifikasi</h1>

      <div className="mt-6">
        <NotificationPreferences />
      </div>
    </main>
  );
}
