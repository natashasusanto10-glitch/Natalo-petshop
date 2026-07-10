import { requireAdminSession } from "@/lib/session-guards";
import {
  PageHeader,
  SectionCard,
  Badge,
  Button,
  AdminPage,
} from "@/components/admin/ui";

export default async function AdminSettingsPage() {
  await requireAdminSession();

  const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "-";

  return (
    <AdminPage maxWidth="md">
      <PageHeader
        title="⚙️ Pengaturan Toko"
        subtitle="Konfigurasi umum toko kamu. Sebagian dikontrol via env vars di server."
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            ← Dashboard
          </Button>
        }
      />

      <div className="mt-6 space-y-4">
        <SectionCard
          title="Informasi Toko"
          subtitle="Ubah nilai ini melalui file .env di server."
        >
          <div className="space-y-3">
            <div className="rounded-xl bg-zinc-50 px-4 py-3">
              <p className="text-[11px] font-black uppercase tracking-wider text-zinc-500">
                Nama Toko
              </p>
              <p className="mt-1 font-black text-zinc-900">{brand}</p>
              <p className="mt-0.5 font-mono text-[10px] text-zinc-600">
                NEXT_PUBLIC_BRAND_NAME
              </p>
            </div>
            <div className="rounded-xl bg-zinc-50 px-4 py-3">
              <p className="text-[11px] font-black uppercase tracking-wider text-zinc-500">
                URL Toko
              </p>
              <p className="mt-1 break-all font-black text-zinc-900">
                {siteUrl}
              </p>
              <p className="mt-0.5 font-mono text-[10px] text-zinc-600">
                NEXT_PUBLIC_SITE_URL
              </p>
            </div>
          </div>
        </SectionCard>

        <SectionCard title="Payment Gateway">
          <div className="space-y-2">
            <div className="flex items-center justify-between rounded-xl bg-zinc-50 px-4 py-3">
              <div>
                <p className="font-bold text-zinc-900">Midtrans</p>
                <p className="text-xs text-zinc-500">
                  Kartu kredit, transfer, e-wallet
                </p>
              </div>
              <Badge variant="neutral" size="md">
                via .env
              </Badge>
            </div>
          </div>
        </SectionCard>

        <SectionCard title="Pengiriman">
          <div className="space-y-2">
            <div className="flex items-center justify-between rounded-xl bg-zinc-50 px-4 py-3">
              <div>
                <p className="font-bold text-zinc-900">Biteship</p>
                <p className="text-xs text-zinc-500">
                  Kalkulasi ongkos kirim multi-kurir
                </p>
              </div>
              <Badge variant="neutral" size="md">
                via .env
              </Badge>
            </div>
          </div>
        </SectionCard>

        <p className="rounded-xl border border-zinc-200 bg-zinc-50/50 px-4 py-3 text-center text-xs font-medium text-zinc-500">
          ℹ️ Fitur pengaturan langsung dari UI akan segera hadir.
        </p>
      </div>
    </AdminPage>
  );
}
