/**
 * Satu sumber kebenaran untuk cocokkan voucher scoped (Target Product /
 * Kategori / Brand) ke produk. Sebelumnya logika ini terduplikasi di 4
 * tempat berbeda (lib/product-vouchers.ts, app/api/checkout/recalculate,
 * app/api/orders, lib/refund-wallet.ts) — pola yang sama persis dengan
 * bug 3-search-engine-berbeda yang pernah ditemukan. Konsolidasi ke sini
 * supaya menambah dimensi target baru (mis. brand) cukup di SATU tempat.
 *
 * Aturan: kosongkan SEMUA (productIds + categoryIds + brandIds) = voucher
 * berlaku untuk semua produk. Kalau salah satu diisi, produk match kalau
 * cocok ke SALAH SATU dimensi yang diisi (OR antar dimensi).
 */

export type VoucherEligibilityScope = {
  eligibleProductIds: string[];
  eligibleCategoryIds: string[];
  eligibleBrandIds: string[];
};

export type EligibilityProductInput = {
  id: string;
  categoryId?: string | null;
  categorySlug?: string | null;
  brandId?: string | null;
};

export function voucherMatchesProduct(
  voucher: VoucherEligibilityScope,
  product: EligibilityProductInput
): boolean {
  const productIds = new Set(voucher.eligibleProductIds ?? []);
  const categoryIds = new Set(voucher.eligibleCategoryIds ?? []);
  const brandIds = new Set(voucher.eligibleBrandIds ?? []);

  if (productIds.size === 0 && categoryIds.size === 0 && brandIds.size === 0) {
    return true;
  }
  if (productIds.has(product.id)) return true;
  if (product.categoryId && categoryIds.has(product.categoryId)) return true;
  // Safety untuk data lama/admin input manual yang mungkin memakai slug.
  if (product.categorySlug && categoryIds.has(product.categorySlug)) return true;
  if (product.brandId && brandIds.has(product.brandId)) return true;
  return false;
}
