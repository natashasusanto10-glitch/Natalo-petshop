import { requireAdminSession } from "@/lib/session-guards";

export default async function AdminSettingsPage() {
  await requireAdminSession();

  const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "-";

  return (
    <div className="mx-auto max-w-2xl px-4 py-5 md:py-10">
      <div>
        <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
          Pengaturan Toko
        </h1>
        <p className="mt-1 text-sm text-zinc-500">
          Konfigurasi umum toko kamu.
        </p>
      </div>

      {/* Current config (read-only display) */}
      <section className="mt-5 rounded-2xl border border-zinc-200 bg-white p-4 md:mt-6 md:rounded-3xl md:p-6">
        <h2 className="font-bold text-zinc-950">Informasi Toko</h2>
        <p className="mt-1 text-xs text-zinc-400">
          Ubah nilai ini melalui file{" "}
          <code className="rounded bg-zinc-100 px-1 py-0.5">.env</code> di
          server.
        </p>

        <div className="mt-5 space-y-4">
          <div className="rounded-2xl bg-zinc-50 px-4 py-3">
            <p className="text-xs font-semibold text-zinc-500">Nama Toko</p>
            <p className="mt-1 font-semibold text-zinc-900">{brand}</p>
            <p className="text-xs text-zinc-400">NEXT_PUBLIC_BRAND_NAME</p>
          </div>
          <div className="rounded-2xl bg-zinc-50 px-4 py-3">
            <p className="text-xs font-semibold text-zinc-500">URL Toko</p>
            <p className="mt-1 font-semibold text-zinc-900">{siteUrl}</p>
            <p className="text-xs text-zinc-400">NEXT_PUBLIC_SITE_URL</p>
          </div>
        </div>
      </section>

      {/* Payment gateways */}
      <section className="mt-4 rounded-2xl border border-zinc-200 bg-white p-4 md:rounded-3xl md:p-6">
        <h2 className="font-bold text-zinc-950">Payment Gateway</h2>
        <div className="mt-5 space-y-3">
          {[
            {
              name: "Midtrans",
              key: "MIDTRANS_SERVER_KEY",
              desc: "Kartu kredit, transfer, e-wallet",
            },
          ].map((gw) => (
            <div
              key={gw.name}
              className="flex items-center justify-between rounded-2xl bg-zinc-50 px-4 py-3"
            >
              <div>
                <p className="font-semibold text-zinc-900">{gw.name}</p>
                <p className="text-xs text-zinc-400">{gw.desc}</p>
              </div>
              <span className="rounded-full bg-zinc-200 px-2.5 py-1 text-xs font-bold text-zinc-600">
                via .env
              </span>
            </div>
          ))}
        </div>
      </section>

      {/* Shipping */}
      <section className="mt-4 rounded-2xl border border-zinc-200 bg-white p-4 md:rounded-3xl md:p-6">
        <h2 className="font-bold text-zinc-950">Pengiriman</h2>
        <div className="mt-5 space-y-3">
          {[
            {
              name: "RajaOngkir",
              key: "RAJAONGKIR_API_KEY",
              desc: "Kalkulasi ongkos kirim",
            },
          ].map((svc) => (
            <div
              key={svc.name}
              className="flex items-center justify-between rounded-2xl bg-zinc-50 px-4 py-3"
            >
              <div>
                <p className="font-semibold text-zinc-900">{svc.name}</p>
                <p className="text-xs text-zinc-400">{svc.desc}</p>
              </div>
              <span className="rounded-full bg-zinc-200 px-2.5 py-1 text-xs font-bold text-zinc-600">
                via .env
              </span>
            </div>
          ))}
        </div>
      </section>

      <p className="mt-6 text-center text-xs text-zinc-400">
        Fitur pengaturan langsung dari UI akan segera hadir.
      </p>
    </div>
  );
}
