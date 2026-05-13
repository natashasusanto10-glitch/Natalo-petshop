import type { Metadata } from "next";
import { NotificationsList } from "@/components/NotificationsList";

export const metadata: Metadata = {
  title: "Notifikasi",
  robots: { index: false, follow: false },
};

export default function NotificationsPage() {
  return (
    <main className="min-h-screen bg-slate-50 pb-[calc(6rem+env(safe-area-inset-bottom))]">
      <NotificationsList />
    </main>
  );
}
