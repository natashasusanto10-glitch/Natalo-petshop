import { AdminPage } from "@/components/admin/ui";
import type { Metadata } from "next";
import { AdminFeedCreateClient } from "@/components/admin/feed/AdminFeedCreateClient";

export const metadata: Metadata = {
  title: "Buat Post Feed — Admin Natalo",
};

export default function AdminFeedNewPage() {
  return (
    <AdminPage maxWidth="lg" className="admin-operational-page">
      <AdminFeedCreateClient />
    </AdminPage>
  );
}
