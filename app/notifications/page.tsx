import type { Metadata } from "next";
import { NotificationsList } from "@/components/NotificationsList";

export const metadata: Metadata = {
  title: "Notifikasi",
  robots: { index: false, follow: false },
};

export default function NotificationsPage() {
  return (
    <main className="h-[100dvh] overflow-hidden bg-slate-50">
      <NotificationsList />
    </main>
  );
}
