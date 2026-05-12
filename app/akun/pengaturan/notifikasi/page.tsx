import type { Metadata } from "next";
import Link from "next/link";
import { requireCustomerSession } from "@/lib/session-guards";
import { NotificationSettingsClient } from "@/components/NotificationSettingsClient";

export const metadata: Metadata = {
  title: "Pengaturan Notifikasi",
};

export default async function NotificationSettingsPage() {
  await requireCustomerSession();

  return (
    <div className="mx-auto max-w-2xl px-4 py-4 md:py-10">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.18em] text-blue-600">
            Pengaturan
          </p>
          <h1 className="mt-1 text-xl font-black text-gray-950 md:text-2xl">
            Notifikasi
          </h1>
        </div>
        <Link
          href="/member"
          className="rounded-full border border-gray-200 px-4 py-2 text-xs font-bold text-gray-700 hover:border-blue-300 hover:text-blue-700"
        >
          Kembali
        </Link>
      </div>

      <div className="mt-5">
        <NotificationSettingsClient />
      </div>
    </div>
  );
}
