import type { Metadata } from "next";
import { requireCustomerSession } from "@/lib/session-guards";
import { NotificationSettingsClient } from "@/components/NotificationSettingsClient";
import { StickyBackTitle } from "@/components/StickyBackTitle";

export const metadata: Metadata = {
  title: "Pengaturan Notifikasi",
};

export default async function NotificationSettingsPage() {
  await requireCustomerSession();

  return (
    <main className="min-h-screen bg-slate-50 pb-24">
      <StickyBackTitle label="Pengaturan Notifikasi" href="/member" stickToTop />
      <div className="mx-auto max-w-2xl px-4 py-5 md:py-10">
        <NotificationSettingsClient />
      </div>
    </main>
  );
}
