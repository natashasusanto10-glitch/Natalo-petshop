import { requireAdminSession } from "@/lib/session-guards";
import { SettingsView } from "@/components/admin/views/SettingsView";
export default async function AdminSettingsPage() {
  await requireAdminSession();
  return (
    <SettingsView
      brand={process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop"}
      siteUrl={process.env.NEXT_PUBLIC_SITE_URL || "—"}
    />
  );
}
