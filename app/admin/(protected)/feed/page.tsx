import type { Metadata } from "next";
import { AdminFeedClient } from "@/components/admin/feed/AdminFeedClient";

export const metadata: Metadata = {
  title: "Feed — Admin Natalo",
};

export default function AdminFeedPage() {
  return (
    <main className="min-h-[100dvh] bg-slate-50 px-4 pb-24 pt-4">
      <AdminFeedClient />
    </main>
  );
}
