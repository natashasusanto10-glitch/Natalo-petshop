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
        title="Pengaturan Toko"
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
          <div className="space-y-2">
            <SettingRow label="Nama Toko" value={brand} envVar="NEXT_PUBLIC_BRAND_NAME" />
            <SettingRow label="URL Toko" value={siteUrl} envVar="NEXT_PUBLIC_SITE_URL" breakAll />
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

        <p className="rounded-xl border border-dashed border-zinc-200 px-4 py-3 text-center text-xs font-medium text-zinc-400">
          Fitur pengaturan langsung dari UI akan segera hadir.
        </p>
      </div>
    </AdminPage>
  );
}

/** Baris label/value + badge nama env var — dipakai supaya ritme visual
 * sama dengan section Payment Gateway/Pengiriman (label+deskripsi kiri,
 * badge kanan), bukan tumpukan 3 baris teks bersaing bobot. */
function SettingRow({
  label,
  value,
  envVar,
  breakAll,
}: {
  label: string;
  value: string;
  envVar: string;
  breakAll?: boolean;
}) {
  return (
    <div className="flex items-center justify-between gap-3 rounded-xl bg-zinc-50 px-4 py-3">
      <div className="min-w-0">
        <p className="text-[11px] font-bold uppercase tracking-wider text-zinc-500">
          {label}
        </p>
        <p className={`mt-0.5 font-black text-zinc-900 ${breakAll ? "break-all" : "truncate"}`}>
          {value}
        </p>
      </div>
      <div className="hidden shrink-0 sm:block">
        <Badge variant="neutral" size="sm">
          <span className="font-mono">{envVar}</span>
        </Badge>
      </div>
    </div>
  );
}
