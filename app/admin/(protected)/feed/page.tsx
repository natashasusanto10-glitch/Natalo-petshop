import type { Metadata } from "next";
import { AdminFeedClient } from "@/components/admin/feed/AdminFeedClient";
import { AdminPage } from "@/components/admin/ui";

export const metadata: Metadata = {
  title: "Feed — Admin Natalo",
};

export default function AdminFeedPage() {
  return (
    <AdminPage maxWidth="lg">
      <AdminFeedClient />
    </AdminPage>
  );
}
