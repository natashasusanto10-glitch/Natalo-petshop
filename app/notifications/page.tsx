import type { Metadata } from "next";
import { NotificationsList } from "@/components/NotificationsList";
import { requireCustomerSession } from "@/lib/session-guards";

export const metadata: Metadata = {
  title: "Notifikasi",
  robots: { index: false, follow: false },
};

export default async function NotificationsPage() {
  // Self-guard (bukan andalkan notifications/layout.tsx) — konsisten dengan
  // notifications/[id]/page.tsx yang butuh returnTo presisi per-pengumuman;
  // layout tidak bisa kirim path presisi dan selalu jalan duluan.
  await requireCustomerSession("/notifications");
  return (
    <main className="h-[100dvh] overflow-hidden bg-slate-50">
      <NotificationsList />
    </main>
  );
}
