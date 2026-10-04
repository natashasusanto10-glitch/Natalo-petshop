import {
  AdminPage,
  PageHeader,
  SectionCard,
  Badge,
  Button,
} from "@/components/admin/ui";

export function SettingsView({
  brand,
  siteUrl,
}: {
  brand: string;
  siteUrl: string;
}) {
  return (
    <AdminPage
      maxWidth="lg"
      className="admin-operational-page admin-refined-page"
    >
      <PageHeader
        eyebrow="Workspace"
        title="Pengaturan toko"
        subtitle="Informasi toko dan layanan yang digunakan."
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            Kembali ke ringkasan
          </Button>
        }
      />
      <div className="admin-settings-grid">
        <SectionCard
          title="Identitas toko"
          subtitle="Informasi yang tampil kepada pelanggan."
        >
          <dl className="admin-definition-list">
            <div>
              <dt>Nama toko</dt>
              <dd>{brand}</dd>
            </div>
            <div>
              <dt>Alamat website</dt>
              <dd className="break-all">{siteUrl}</dd>
            </div>
          </dl>
        </SectionCard>
        <SectionCard
          title="Layanan toko"
          subtitle="Penyedia pembayaran dan pengiriman."
        >
          <div className="admin-service-row">
            <div>
              <h3>Midtrans</h3>
              <p>Pembayaran kartu, transfer, dan e-wallet.</p>
            </div>
            <Badge>Pembayaran</Badge>
          </div>
          <div className="admin-service-row">
            <div>
              <h3>Biteship</h3>
              <p>Ongkos kirim dan layanan multi-kurir.</p>
            </div>
            <Badge>Pengiriman</Badge>
          </div>
        </SectionCard>
      </div>
      <SectionCard
        title="Pengelolaan"
        className="mt-6"
        subtitle="Akses catatan operasional dan pemeriksaan akun."
      >
        <div className="flex flex-wrap gap-3">
          <Button href="/admin/audit-log" variant="secondary">
            Riwayat aktivitas
          </Button>
          <Button href="/admin/abuse-flags" variant="secondary">
            Indikasi penyalahgunaan
          </Button>
        </div>
        <p className="mt-5 text-sm leading-relaxed text-slate-600">
          Informasi dan koneksi layanan pada halaman ini bersifat baca saja.
          Hubungi pengelola sistem untuk mengubah konfigurasi toko.
        </p>
      </SectionCard>
    </AdminPage>
  );
}
