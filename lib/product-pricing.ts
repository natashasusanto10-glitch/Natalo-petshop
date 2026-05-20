/**
 * Product pricing utility — resolve harga efektif berdasarkan promo
 * yang sedang aktif. Priority: pick LOWEST price (customer-friendly)
 * dari semua sumber promo yang berlaku.
 *
 * Sumber promo:
 *   1. Flash Sale  — Product.flashSaleEndsAt > now + Product.discountPrice
 *   2. Promo Toko  — ProductDiscountItem active dengan match productId
 *                    (+ variantId kalau berVarian)
 *
 * Kalau dua-duanya aktif, yang harga terendah menang. Sumber dipakai
 * untuk decide apakah countdown timer ditampilkan (Flash Sale = ya,
 * Promo Toko = no).
 */

export type DiscountSource = "FLASH_SALE" | "PROMO_TOKO";

export interface ActiveDiscount {
  source: DiscountSource;
  /** Harga setelah diskon (final). */
  effectivePrice: number;
  /** Selisih harga vs base. */
  discountAmount: number;
  /** Persentase diskon (rounded). */
  discountPercent: number;
  /** Waktu berakhir promo. Untuk FLASH_SALE dipakai countdown timer.
   *  Untuk PROMO_TOKO biasanya periode lebih panjang, optional display. */
  endsAt: Date;
}

/**
 * Resolve discount aktif untuk satu produk/varian.
 *
 * @param basePrice  Harga base (product.price atau variant.price)
 * @param flashSale  Data Flash Sale dari Product fields
 * @param promoItems Active ProductDiscountItem yang match product+variant
 * @param now        Optional, default = sekarang
 *
 * @returns ActiveDiscount kalau ada promo aktif yang turunin harga,
 *          null kalau tidak.
 */
export function resolveActiveDiscount(
  basePrice: number,
  flashSale: { discountPrice: number | null; endsAt: Date | null },
  promoItems: Array<{ discountedPrice: number; endsAt: Date }>,
  now: Date = new Date(),
): ActiveDiscount | null {
  let best: ActiveDiscount | null = null;

  // Flash Sale candidate
  if (
    flashSale.endsAt &&
    flashSale.endsAt > now &&
    flashSale.discountPrice &&
    flashSale.discountPrice > 0 &&
    flashSale.discountPrice < basePrice
  ) {
    best = {
      source: "FLASH_SALE",
      effectivePrice: flashSale.discountPrice,
      discountAmount: basePrice - flashSale.discountPrice,
      discountPercent: Math.round(
        ((basePrice - flashSale.discountPrice) / basePrice) * 100,
      ),
      endsAt: flashSale.endsAt,
    };
  }

  // Promo Toko candidates — pick lowest among active
  for (const item of promoItems) {
    if (item.endsAt <= now) continue;
    if (item.discountedPrice <= 0) continue;
    if (item.discountedPrice >= basePrice) continue;
    if (!best || item.discountedPrice < best.effectivePrice) {
      best = {
        source: "PROMO_TOKO",
        effectivePrice: item.discountedPrice,
        discountAmount: basePrice - item.discountedPrice,
        discountPercent: Math.round(
          ((basePrice - item.discountedPrice) / basePrice) * 100,
        ),
        endsAt: item.endsAt,
      };
    }
  }

  return best;
}
