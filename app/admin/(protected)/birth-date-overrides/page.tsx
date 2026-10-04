import BirthDateOverrideClient from "./BirthDateOverrideClient";
import { PageHeader, Button, AdminPage } from "@/components/admin/ui";

export const dynamic = "force-dynamic";

export default function BirthDateOverridePage() {
  return (
    <AdminPage maxWidth="lg" className="admin-operational-page">
      <div>
        <PageHeader
          title="Koreksi tanggal lahir"
          subtitle="Perbarui tanggal lahir pelanggan melalui layanan pelanggan. Perubahan tercatat dalam riwayat aktivitas."
          actions={
            <Button href="/admin/dashboard" variant="secondary" size="sm">
              Kembali ke ringkasan
            </Button>
          }
        />
      </div>
      <BirthDateOverrideClient />
    </AdminPage>
  );
}
