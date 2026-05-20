/**
 * /admin/diskon — Hub Buat Diskon
 *
 * Landing page terpusat untuk semua jenis promosi toko ala Shopee
 * Seller Centre. Group 4 modul promo:
 *
 *   1. Promo Toko    — diskon harga coret per-produk (ProductDiscount)
 *   2. Voucher Toko  — kode kupon (link ke /admin/vouchers existing)
 *   3. Flash Sale    — pakai field Product.flashSaleEndsAt existing
 *   4. Paket Diskon  — bundle multi-tier (coming soon, Phase 3)
 *
 * Tabs untuk filter status. Performa Promosi widget (analytics stub
 * dulu — akan di-wire ke real metrics di iterasi berikutnya). Daftar
 * Promosi unified table — gabungin sumber data dari beberapa model.
 */
import Link from "next/link";
import { prisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

type PromoRow = {
  id: string;
  kind: "PROMO_TOKO" | "VOUCHER" | "FLASH_SALE" | "PAKET_DISKON";
  name: string;
  status: "UPCOMING" | "ONGOING" | "EXPIRED";
  productThumbnails: string[];
  productCount: number;
  startsAt: Date | null;
  endsAt: Date | null;
  editHref: string;
};

function statusOf(startsAt: Date | null, endsAt: Date | null): PromoRow["status"] {
  const now = new Date();
  if (endsAt && endsAt < now) return "EXPIRED";
  if (startsAt && startsAt > now) return "UPCOMING";
  return "ONGOING";
}

function formatDateTime(d: Date | null) {
  if (!d) return "—";
  return d.toLocaleString("id-ID", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export default async function AdminDiskonHub() {
  // ── Aggregate data dari semua jenis promo ──────────────────────
  // Voucher dari model Voucher existing.
  const vouchersRaw = await prisma.voucher.findMany({
    where: {
      // Hanya yang admin-managed (sourceType bukan customer claim
      // birthday/poin). Filter aman untuk avoid clutter di hub.
      userId: null,
    },
    orderBy: { createdAt: "desc" },
    take: 50,
    select: {
      id: true,
      name: true,
      code: true,
      startsAt: true,
      expiresAt: true,
      isActive: true,
      eligibleProductIds: true,
    },
  });

  // Flash sale: produk dengan flashSaleEndsAt > now (atau yang scheduled
  // future). Pakai threshold 7 hari kebelakang untuk include yg baru
  // expired juga supaya admin bisa lihat history singkat.
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const flashSaleProducts = await prisma.product.findMany({
    where: {
      flashSaleEndsAt: { gte: sevenDaysAgo },
    },
    orderBy: { flashSaleEndsAt: "desc" },
    take: 50,
    select: {
      id: true,
      name: true,
      imageUrl: true,
      flashSaleEndsAt: true,
      discountPrice: true,
      price: true,
    },
  });

  // ── Aggregate metrics (stub — placeholder data) ─────────────────
  // TODO: integrate dengan real order metrics filter promosi.
  // Untuk Phase 1, tampilkan dash supaya admin tahu widget ini akan
  // diisi data nanti. Periode default 7 hari terakhir.
  const performaPeriode = {
    start: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
    end: new Date(),
  };

  // ── Map ke PromoRow unified format ──────────────────────────────
  const rows: PromoRow[] = [
    ...vouchersRaw.map<PromoRow>((v) => ({
      id: `voucher-${v.id}`,
      kind: "VOUCHER",
      name: v.name || v.code,
      status: !v.isActive
        ? "EXPIRED"
        : statusOf(v.startsAt, v.expiresAt),
      productThumbnails: [],
      productCount: v.eligibleProductIds.length,
      startsAt: v.startsAt,
      endsAt: v.expiresAt,
      editHref: `/admin/vouchers/${v.id}/edit`,
    })),
    ...flashSaleProducts.map<PromoRow>((p) => ({
      id: `flash-${p.id}`,
      kind: "FLASH_SALE",
      name: p.name,
      status: statusOf(null, p.flashSaleEndsAt),
      productThumbnails: p.imageUrl ? [p.imageUrl] : [],
      productCount: 1,
      startsAt: null,
      endsAt: p.flashSaleEndsAt,
      editHref: `/admin/products/${p.id}/edit`,
    })),
  ].sort((a, b) => {
    // Active dulu, lalu upcoming, lalu expired. Dalam satu group urutkan
    // by endsAt desc supaya yang baru di atas.
    const statusOrder = { ONGOING: 0, UPCOMING: 1, EXPIRED: 2 };
    const so = statusOrder[a.status] - statusOrder[b.status];
    if (so !== 0) return so;
    return (b.endsAt?.getTime() ?? 0) - (a.endsAt?.getTime() ?? 0);
  });

  return (
    <div className="mx-auto max-w-7xl px-4 py-5 md:px-8 md:py-10">
      {/* ── Header ──────────────────────────────────────────────── */}
      <div className="flex flex-col items-start justify-between gap-2 md:flex-row md:items-end">
        <div>
          <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:text-3xl">
            Buat Diskon
          </h1>
          <p className="mt-1 text-sm text-zinc-500">
            Buat diskon sendiri untuk meningkatkan penjualan!
          </p>
        </div>
      </div>

      {/* ── 4 Quick Action Cards ────────────────────────────────── */}
      <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <PromoTypeCard
          icon="🏷"
          title="Promo Toko"
          desc="Diskon harga coret per-produk dengan periode tertentu."
          ctaHref="/admin/diskon/promo-toko/new"
          ctaLabel="Buat"
          ctaDisabled={false}
          comingSoon={false}
        />
        <PromoTypeCard
          icon="🎫"
          title="Voucher Toko"
          desc="Kode kupon untuk diskon di checkout."
          ctaHref="/admin/vouchers/new"
          ctaLabel="Buat"
          ctaDisabled={false}
          comingSoon={false}
        />
        <PromoTypeCard
          icon="⚡"
          title="Flash Sale"
          desc="Diskon terbatas waktu dengan countdown timer."
          ctaHref="/admin/diskon/flash-sale/new"
          ctaLabel="Buat"
          ctaDisabled={false}
          comingSoon={false}
        />
        <PromoTypeCard
          icon="📦"
          title="Paket Diskon"
          desc="Multi-tier bundle deal — beli X hemat Y."
          ctaHref="#"
          ctaLabel="Coming soon"
          ctaDisabled={true}
          comingSoon={true}
        />
      </div>

      {/* ── Performa Promosi ────────────────────────────────────── */}
      <div className="mt-8">
        <div className="flex items-baseline justify-between">
          <div>
            <h2 className="text-base font-bold text-zinc-900">
              Performa Promosi
            </h2>
            <p className="mt-0.5 text-xs text-zinc-500">
              ({formatDateTime(performaPeriode.start)} sampai{" "}
              {formatDateTime(performaPeriode.end)} GMT+7)
            </p>
          </div>
          <button
            type="button"
            className="text-sm font-semibold text-natalo-600 hover:text-natalo-700"
          >
            Lainnya ›
          </button>
        </div>
        <div className="mt-3 grid gap-3 rounded-2xl border border-zinc-200 bg-white p-4 sm:grid-cols-2 lg:grid-cols-4">
          <MetricCard label="Penjualan" value="Rp —" compare="vs 7 hari terakhir" />
          <MetricCard label="Pesanan" value="—" compare="vs 7 hari terakhir" />
          <MetricCard label="Jumlah Terjual" value="—" compare="vs 7 hari terakhir" />
          <MetricCard label="Pembeli" value="—" compare="vs 7 hari terakhir" />
        </div>
        <p className="mt-2 text-xs text-zinc-400">
          ⓘ Metrik analytics akan diaktifkan setelah integrasi tracking
          per-promo. Untuk sementara, lihat performa di Laporan.
        </p>
      </div>

      {/* ── Daftar Promosi (unified table) ──────────────────────── */}
      <div className="mt-8">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-bold text-zinc-900">
            Daftar Promosi
          </h2>
          <div className="text-xs text-zinc-500">
            {rows.length} promosi
          </div>
        </div>

        {/* Filter bar (stub — Phase 2: wire up search + date filter) */}
        <div className="mt-3 flex flex-wrap items-center gap-2 rounded-xl border border-zinc-200 bg-zinc-50/60 p-3">
          <span className="text-xs font-semibold text-zinc-500">Cari</span>
          <input
            type="text"
            placeholder="Nama promosi..."
            className="flex-1 rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-natalo-600"
          />
          <input
            type="text"
            placeholder="Periode (mm/yyyy)"
            className="rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-natalo-600 sm:w-48"
          />
          <button
            type="button"
            className="rounded-lg bg-natalo-600 px-4 py-2 text-sm font-bold text-white hover:bg-natalo-700"
          >
            Cari
          </button>
          <button
            type="button"
            className="rounded-lg border border-zinc-300 bg-white px-4 py-2 text-sm font-bold text-zinc-700 hover:bg-zinc-50"
          >
            Atur ulang
          </button>
        </div>

        {/* Table */}
        <div className="mt-3 overflow-x-auto rounded-xl border border-zinc-200 bg-white">
          <table className="w-full text-sm">
            <thead className="bg-zinc-50 text-xs font-bold uppercase tracking-wide text-zinc-500">
              <tr>
                <th className="px-4 py-3 text-left">Status + Nama</th>
                <th className="px-4 py-3 text-left">Tipe Promosi</th>
                <th className="px-4 py-3 text-left">Produk</th>
                <th className="px-4 py-3 text-left">Periode</th>
                <th className="px-4 py-3 text-right">Aksi</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-100">
              {rows.length === 0 && (
                <tr>
                  <td
                    colSpan={5}
                    className="px-4 py-12 text-center text-sm text-zinc-400"
                  >
                    Belum ada promosi. Klik tombol{" "}
                    <strong>Buat</strong> di atas untuk mulai.
                  </td>
                </tr>
              )}
              {rows.map((row) => (
                <tr key={row.id} className="hover:bg-zinc-50/50">
                  <td className="px-4 py-3 align-top">
                    <StatusBadge status={row.status} />
                    <p className="mt-1 font-semibold text-zinc-900">
                      {row.name}
                    </p>
                  </td>
                  <td className="px-4 py-3 align-top">
                    <KindBadge kind={row.kind} />
                  </td>
                  <td className="px-4 py-3 align-top">
                    {row.productThumbnails.length > 0 ? (
                      <div className="flex items-center gap-1">
                        {row.productThumbnails.slice(0, 3).map((url, i) => (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img
                            key={i}
                            src={url}
                            alt=""
                            className="h-8 w-8 rounded border border-zinc-200 object-cover"
                          />
                        ))}
                        {row.productCount > 3 && (
                          <span className="text-xs font-bold text-zinc-400">
                            +{row.productCount - 3}
                          </span>
                        )}
                      </div>
                    ) : (
                      <span className="text-xs text-zinc-400">
                        {row.productCount > 0
                          ? `${row.productCount} produk`
                          : "Semua produk"}
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-3 align-top text-xs text-zinc-600">
                    {row.startsAt && (
                      <>
                        {formatDateTime(row.startsAt)}
                        <br />→{" "}
                      </>
                    )}
                    {formatDateTime(row.endsAt)}
                  </td>
                  <td className="px-4 py-3 align-top text-right">
                    <Link
                      href={row.editHref}
                      className="text-sm font-semibold text-natalo-600 hover:text-natalo-700"
                    >
                      {row.status === "EXPIRED" ? "Lihat" : "Ubah"}
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

// ── Sub-components ───────────────────────────────────────────────

function PromoTypeCard({
  icon,
  title,
  desc,
  ctaHref,
  ctaLabel,
  ctaDisabled,
  comingSoon,
}: {
  icon: string;
  title: string;
  desc: string;
  ctaHref: string;
  ctaLabel: string;
  ctaDisabled: boolean;
  comingSoon: boolean;
}) {
  return (
    <div
      className={`rounded-2xl border bg-white p-4 ${
        comingSoon ? "border-zinc-200 opacity-70" : "border-zinc-200"
      }`}
    >
      <div className="flex items-start gap-3">
        <span className="text-2xl">{icon}</span>
        <div className="min-w-0 flex-1">
          <h3 className="text-sm font-black text-zinc-900">{title}</h3>
          <p className="mt-0.5 text-xs leading-relaxed text-zinc-500">
            {desc}
          </p>
        </div>
      </div>
      <div className="mt-4 flex justify-end">
        {ctaDisabled ? (
          <span className="cursor-not-allowed rounded-lg bg-zinc-100 px-4 py-2 text-xs font-bold text-zinc-400">
            {ctaLabel}
          </span>
        ) : (
          <Link
            href={ctaHref}
            className="rounded-lg bg-natalo-600 px-4 py-2 text-xs font-bold text-white hover:bg-natalo-700"
          >
            {ctaLabel}
          </Link>
        )}
      </div>
    </div>
  );
}

function MetricCard({
  label,
  value,
  compare,
}: {
  label: string;
  value: string;
  compare: string;
}) {
  return (
    <div>
      <p className="text-xs font-semibold text-zinc-500">{label} ⓘ</p>
      <p className="mt-1 text-2xl font-black text-zinc-900">{value}</p>
      <p className="mt-1 text-[11px] text-zinc-400">{compare}</p>
    </div>
  );
}

function StatusBadge({ status }: { status: PromoRow["status"] }) {
  const styles = {
    ONGOING: "bg-green-50 text-green-700",
    UPCOMING: "bg-amber-50 text-amber-700",
    EXPIRED: "bg-zinc-100 text-zinc-500",
  };
  const labels = {
    ONGOING: "Sedang Berjalan",
    UPCOMING: "Akan Datang",
    EXPIRED: "Telah Berakhir",
  };
  return (
    <span
      className={`inline-block rounded-md px-2 py-0.5 text-[10px] font-bold ${styles[status]}`}
    >
      {labels[status]}
    </span>
  );
}

function KindBadge({ kind }: { kind: PromoRow["kind"] }) {
  const labels = {
    PROMO_TOKO: "Promo Toko",
    VOUCHER: "Voucher",
    FLASH_SALE: "Flash Sale",
    PAKET_DISKON: "Paket Diskon",
  };
  return (
    <span className="text-xs font-semibold text-zinc-700">{labels[kind]}</span>
  );
}
