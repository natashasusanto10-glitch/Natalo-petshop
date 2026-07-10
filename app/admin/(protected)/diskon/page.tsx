/**
 * /admin/diskon — Hub Buat Diskon
 *
 * Landing page terpusat untuk semua jenis promosi toko ala Shopee
 * Seller Centre. Compact layout:
 *
 *  1. Header
 *  2. 4 Quick Action Cards (Promo Toko / Voucher / Flash Sale / Paket)
 *  3. Performa Promosi widget (analytics stub)
 *  4. Daftar Promosi — COMPACT: 4 summary cards per tipe, klik → drill
 *     down ke list page dedicated per tipe.
 *
 *     Sebelumnya tampilkan semua promo individual sebagai row → jadi
 *     panjang kalau banyak voucher / flash sale. Sekarang group by
 *     tipe + tombol "Lihat semua" untuk navigasi.
 */
import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { getPerformaMetrics } from "@/lib/promo-analytics";
import { formatRupiah } from "@/lib/format";
import { PageHeader, AdminPage, Button } from "@/components/admin/ui";

export const dynamic = "force-dynamic";

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
  // ── Aggregate counts per tipe (untuk summary cards) ─────────────
  const now = new Date();

  // Voucher: admin-managed only (sourceType bukan customer claim).
  const [voucherActive, voucherTotal] = await Promise.all([
    prisma.voucher.count({
      where: {
        userId: null,
        isActive: true,
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
    }),
    prisma.voucher.count({
      where: { userId: null },
    }),
  ]);

  // Promo Toko (ProductDiscount baru).
  const [promoTokoActive, promoTokoTotal] = await Promise.all([
    prisma.productDiscount.count({
      where: {
        isActive: true,
        startsAt: { lte: now },
        endsAt: { gt: now },
      },
    }),
    prisma.productDiscount.count(),
  ]);

  // Flash sale: produk dengan flashSaleEndsAt > now (still active).
  const [flashSaleActive, flashSaleTotal] = await Promise.all([
    prisma.product.count({
      where: { flashSaleEndsAt: { gt: now } },
    }),
    prisma.product.count({
      where: { flashSaleEndsAt: { not: null } },
    }),
  ]);

  // ── Aggregate metrics — REAL data dari Order table ──────────────
  // Periode default: 7 hari terakhir. Compare ke 7 hari sebelumnya untuk
  // delta % (vs 7 hari terakhir di label).
  const performaPeriode = {
    start: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
    end: new Date(),
  };
  const performaMetrics = await getPerformaMetrics(
    performaPeriode.start,
    performaPeriode.end,
  );

  return (
    <AdminPage maxWidth="xl">
      <PageHeader
        title="🎁 Buat Diskon"
        subtitle="Hub semua jenis promosi: Promo Toko, Voucher, Flash Sale, dan Paket. Pilih tipe yang sesuai campaign kamu."
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            ← Dashboard
          </Button>
        }
      />

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
        </div>
        <div className="mt-3 grid gap-3 rounded-2xl border border-zinc-200 bg-white p-4 sm:grid-cols-2 lg:grid-cols-4">
          <MetricCard
            label="Penjualan"
            value={formatRupiah(performaMetrics.current.penjualan)}
            deltaPercent={performaMetrics.deltaPercent.penjualan}
            compare="vs 7 hari terakhir"
          />
          <MetricCard
            label="Pesanan"
            value={performaMetrics.current.pesanan.toLocaleString("id-ID")}
            deltaPercent={performaMetrics.deltaPercent.pesanan}
            compare="vs 7 hari terakhir"
          />
          <MetricCard
            label="Jumlah Terjual"
            value={performaMetrics.current.jumlahTerjual.toLocaleString("id-ID")}
            deltaPercent={performaMetrics.deltaPercent.jumlahTerjual}
            compare="vs 7 hari terakhir"
          />
          <MetricCard
            label="Pembeli"
            value={performaMetrics.current.pembeli.toLocaleString("id-ID")}
            deltaPercent={performaMetrics.deltaPercent.pembeli}
            compare="vs 7 hari terakhir"
          />
        </div>
        <p className="mt-2 text-xs text-zinc-600">
          ⓘ Metrik di atas dihitung dari order PAID/PROCESSING/SHIPPED/
          DELIVERED yang include produk yang sedang/pernah masuk promo
          (Flash Sale atau Promo Toko) dalam periode tersebut.
        </p>
      </div>

      {/* ── Daftar Promosi (COMPACT — grouped by type) ──────────── */}
      <div className="mt-8">
        <h2 className="text-base font-bold text-zinc-900">Daftar Promosi</h2>
        <p className="mt-0.5 text-xs text-zinc-500">
          Klik salah satu tipe untuk lihat semua promosi & detail aksinya.
        </p>

        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <PromoSummaryCard
            icon="🏷"
            title="Promo Toko"
            desc="Diskon harga coret per-produk"
            activeCount={promoTokoActive}
            totalCount={promoTokoTotal}
            href="/admin/diskon/promo-toko"
            color="natalo"
          />
          <PromoSummaryCard
            icon="🎫"
            title="Voucher Toko"
            desc="Kode kupon untuk diskon di checkout"
            activeCount={voucherActive}
            totalCount={voucherTotal}
            href="/admin/vouchers"
            color="natalo"
          />
          <PromoSummaryCard
            icon="⚡"
            title="Flash Sale"
            desc="Diskon terbatas waktu"
            activeCount={flashSaleActive}
            totalCount={flashSaleTotal}
            href="/admin/diskon/flash-sale"
            color="amber"
          />
          <PromoSummaryCard
            icon="📦"
            title="Paket Diskon"
            desc="Multi-tier bundle (Coming soon)"
            activeCount={0}
            totalCount={0}
            href="#"
            color="zinc"
            disabled
          />
        </div>
      </div>
    </AdminPage>
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
          <Button href={ctaHref} size="sm">
            {ctaLabel}
          </Button>
        )}
      </div>
    </div>
  );
}

function MetricCard({
  label,
  value,
  compare,
  deltaPercent,
}: {
  label: string;
  value: string;
  compare: string;
  /** Delta % vs previous period. null = no baseline (previous=0). */
  deltaPercent?: number | null;
}) {
  // Color delta: green untuk positive, red untuk negative, zinc untuk 0/null
  const deltaColor =
    deltaPercent === null || deltaPercent === undefined
      ? "text-zinc-400"
      : deltaPercent > 0
        ? "text-green-600"
        : deltaPercent < 0
          ? "text-red-500"
          : "text-zinc-400";
  const deltaText =
    deltaPercent === null || deltaPercent === undefined
      ? "—"
      : deltaPercent > 0
        ? `+${deltaPercent}%`
        : `${deltaPercent}%`;

  return (
    <div>
      <p className="text-xs font-semibold text-zinc-500">{label} ⓘ</p>
      <p className="mt-1 text-2xl font-black text-zinc-900">{value}</p>
      <p className="mt-1 text-[11px]">
        <span className="text-zinc-400">{compare}</span>{" "}
        <span className={`font-bold ${deltaColor}`}>{deltaText}</span>
      </p>
    </div>
  );
}

// Compact summary card — drill-down navigation per promo type.
function PromoSummaryCard({
  icon,
  title,
  desc,
  activeCount,
  totalCount,
  href,
  color,
  disabled,
}: {
  icon: string;
  title: string;
  desc: string;
  activeCount: number;
  totalCount: number;
  href: string;
  color: "natalo" | "amber" | "zinc";
  disabled?: boolean;
}) {
  const accentClass = {
    natalo: "text-natalo-700 bg-natalo-50",
    amber: "text-amber-700 bg-amber-50",
    zinc: "text-zinc-500 bg-zinc-100",
  }[color];

  const Wrapper = disabled
    ? ({ children }: { children: React.ReactNode }) => (
        <div className="block rounded-2xl border border-zinc-200 bg-white p-4 opacity-60">
          {children}
        </div>
      )
    : ({ children }: { children: React.ReactNode }) => (
        <Link
          href={href}
          className="block rounded-2xl border border-zinc-200 bg-white p-4 transition hover:border-natalo-300 hover:shadow-sm"
        >
          {children}
        </Link>
      );

  return (
    <Wrapper>
      <div className="flex items-center gap-3">
        <span className="text-3xl">{icon}</span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <h3 className="text-base font-bold text-zinc-900">{title}</h3>
            {activeCount > 0 && (
              <span
                className={`rounded-full px-2 py-0.5 text-[10px] font-black ${accentClass}`}
              >
                {activeCount} aktif
              </span>
            )}
          </div>
          <p className="mt-0.5 text-xs text-zinc-500">{desc}</p>
          {totalCount > 0 && (
            <p className="mt-1 text-[11px] text-zinc-400">
              Total {totalCount} promosi (termasuk history)
            </p>
          )}
        </div>
        {!disabled && (
          <span className="text-xl font-bold text-zinc-300 group-hover:text-natalo-500">
            →
          </span>
        )}
      </div>
    </Wrapper>
  );
}
