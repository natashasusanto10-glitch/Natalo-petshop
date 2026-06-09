/**
 * Helper untuk hero banner slider Home (admin-managed).
 *
 * linkType + linkValue (structured, disimpan di DB) → href string yang
 * Flutter _onTap() bisa route. Memisahkan storage (structured, gampang
 * di-edit admin + validasi) dari transport (href string yang sudah
 * dipahami client).
 */

export type BannerLinkType =
  | "none"
  | "category"
  | "product"
  | "brand"
  | "promo"
  | "voucher"
  | "loyalty"
  | "url";

export const BANNER_LINK_TYPES: BannerLinkType[] = [
  "none",
  "category",
  "product",
  "brand",
  "promo",
  "voucher",
  "loyalty",
  "url",
];

/** linkType yang BUTUH linkValue (slug/url). Sisanya self-contained. */
export const LINK_TYPES_NEEDING_VALUE: BannerLinkType[] = [
  "category",
  "product",
  "brand",
  "url",
];

/**
 * Konversi linkType+linkValue → href string untuk Flutter.
 * Return null kalau "none" atau value wajib tapi kosong (banner tidak
 * bisa di-tap).
 *
 * Flutter _HeroBanner._onTap() route href:
 *   /products?kategori=X  → katalog filter kategori
 *   /products?brand=X     → katalog filter brand
 *   /products/<slug>      → product detail
 *   /products?diskon=1    → katalog produk diskon (promo)
 *   /member/vouchers      → daftar voucher
 *   /member/loyalty       → tukar poin
 *   https://...           → in-app browser (eksternal)
 */
export function bannerLinkToHref(
  linkType: string,
  linkValue: string | null | undefined,
): string | null {
  const value = (linkValue ?? "").trim();
  switch (linkType) {
    case "category":
      return value ? `/products?kategori=${encodeURIComponent(value)}` : null;
    case "brand":
      return value ? `/products?brand=${encodeURIComponent(value)}` : null;
    case "product":
      return value ? `/products/${encodeURIComponent(value)}` : null;
    case "promo":
      return "/products?diskon=1";
    case "voucher":
      return "/member/vouchers";
    case "loyalty":
      return "/member/loyalty";
    case "url":
      // Hanya izinkan http(s) eksternal — cegah skema aneh (javascript:, dst).
      return /^https?:\/\//i.test(value) ? value : null;
    case "none":
    default:
      return null;
  }
}

/** Validasi linkType + linkValue sebelum simpan (admin API). */
export function validateBannerLink(
  linkType: string,
  linkValue: string | null | undefined,
): { ok: true } | { ok: false; error: string } {
  if (!BANNER_LINK_TYPES.includes(linkType as BannerLinkType)) {
    return { ok: false, error: "Jenis link tidak valid." };
  }
  const value = (linkValue ?? "").trim();
  if (
    LINK_TYPES_NEEDING_VALUE.includes(linkType as BannerLinkType) &&
    value.length === 0
  ) {
    return {
      ok: false,
      error: "Link tujuan wajib diisi untuk jenis ini.",
    };
  }
  if (linkType === "url" && value && !/^https?:\/\//i.test(value)) {
    return { ok: false, error: "URL harus diawali http:// atau https://" };
  }
  return { ok: true };
}
