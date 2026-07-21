import type { Metadata } from "next";
import { AdminReportsClient } from "@/components/admin/feed/AdminReportsClient";
import { AdminPage } from "@/components/admin/ui";

export const metadata: Metadata = {
  title: "Moderasi Laporan — Admin Natalo",
};

export default function AdminFeedReportsPage() {
  return (
    <AdminPage maxWidth="lg">
      <AdminReportsClient />
    </AdminPage>
  );
}
