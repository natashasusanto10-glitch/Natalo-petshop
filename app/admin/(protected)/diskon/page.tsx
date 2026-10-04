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
import { prisma } from "@/lib/prisma";
import { getPerformaMetrics } from "@/lib/promo-analytics";
import { PromotionsView } from "@/components/admin/views/PromotionsView";

export const dynamic = "force-dynamic";

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
    performaPeriode.end
  );

  return (
    <PromotionsView
      voucherActive={voucherActive}
      voucherTotal={voucherTotal}
      promoTokoActive={promoTokoActive}
      promoTokoTotal={promoTokoTotal}
      flashSaleActive={flashSaleActive}
      flashSaleTotal={flashSaleTotal}
      performaPeriode={performaPeriode}
      performaMetrics={performaMetrics}
    />
  );
}
