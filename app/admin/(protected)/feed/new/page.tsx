import type { Metadata } from "next";
import { AdminFeedCreateClient } from "@/components/admin/feed/AdminFeedCreateClient";

export const metadata: Metadata = {
  title: "Buat Post Feed — Admin Natalo",
};

export default function AdminFeedNewPage() {
  return (
    <main className="min-h-[100dvh] bg-slate-50 px-4 pb-32 pt-4">
      <AdminFeedCreateClient />
    </main>
  );
}
