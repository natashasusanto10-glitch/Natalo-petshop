/**
 * Builder murni konten notifikasi promo — dipisah dari dispatch (push-promo.ts)
 * supaya teruji tanpa DB/mock. Semua fungsi deterministik.
 */

/** Format angka Rupiah singkat: 5000 → "Rp5.000". */
function rp(n: number): string {
  return "Rp" + n.toLocaleString("id-ID");
}

export function buildVoucherPromoContent(v: {
  code: string;
  name: string | null;
  kind: string;
  discountPercent: number | null;
  discountAmount: number | null;
}): { title: string; body: string; eventType: string } {
  if (v.kind === "FREE_SHIPPING") {
    return {
      eventType: "voucher_freeship_published",
      title: "🚚 Gratis Ongkir dari Natalo!",
      body: `Voucher gratis ongkir ${v.code} sudah aktif. Klaim sekarang sebelum habis!`,
    };
  }
  const nilai =
    v.discountPercent && v.discountPercent > 0
      ? `Diskon ${v.discountPercent}%`
      : v.discountAmount && v.discountAmount > 0
        ? `Potongan ${rp(v.discountAmount)}`
        : "Voucher diskon";
  return {
    eventType: "voucher_discount_published",
    title: "🎟️ Voucher diskon baru buat kamu",
    body: `${nilai} pakai kode ${v.code}. Klaim sekarang di halaman voucher!`,
  };
}

/** Persen diskon tertinggi across item; null bila tak ada yang bisa dihitung.
 *  Harga asli = variant.price bila item ber-varian, else product.price.
 *  Item dengan harga asli <= 0 atau discountedPrice >= harga asli dilewati. */
export function maxDiscountPercent(
  items: Array<{
    product: { price: number };
    variant: { price: number } | null;
    discountedPrice: number;
  }>,
): number | null {
  let max: number | null = null;
  for (const it of items) {
    const original = it.variant ? it.variant.price : it.product.price;
    if (original <= 0 || it.discountedPrice >= original) continue;
    const pct = Math.round(((original - it.discountedPrice) / original) * 100);
    if (pct <= 0) continue;
    if (max === null || pct > max) max = pct;
  }
  return max;
}

export function buildDiscountPromoContent(
  d: { name: string },
  items: Array<{
    product: { name: string; slug: string; imageUrl: string | null; price: number };
    variant: { price: number } | null;
    discountedPrice: number;
  }>,
): { title: string; body: string; url: string; thumbnailUrl: string | null } {
  const pct = maxDiscountPercent(items);
  const thumbnailUrl = items[0]?.product.imageUrl ?? null;
  if (items.length === 1) {
    const p = items[0].product;
    const pctText = pct ? ` — hemat s/d ${pct}%` : "";
    return {
      title: `🔥 ${p.name} lagi diskon!`,
      body: `Harga spesial${pctText}. Cek sekarang sebelum promo berakhir.`,
      url: `/produk/${p.slug}`,
      thumbnailUrl,
    };
  }
  const pctText = pct ? ` diskon s/d ${pct}%` : " diskon";
  return {
    title: `🔥 Promo Toko: ${items.length} produk diskon`,
    body: `${items.length} produk pilihan${pctText}. Buruan cek sebelum kehabisan!`,
    url: "/products",
    thumbnailUrl,
  };
}

export function isPromoDue(
  row: {
    notifyAtStart: boolean;
    promoNotifiedAt: Date | null;
    isActive: boolean;
    startsAt: Date;
    endsAt: Date | null;
  },
  now: Date,
): boolean {
  if (!row.notifyAtStart) return false;
  if (row.promoNotifiedAt != null) return false;
  if (!row.isActive) return false;
  if (row.startsAt > now) return false;
  if (row.endsAt != null && row.endsAt <= now) return false;
  return true;
}
