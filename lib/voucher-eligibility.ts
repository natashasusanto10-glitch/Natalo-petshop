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

import { prisma } from "@/lib/prisma";

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

/**
 * True kalau voucher di-scope ke produk/kategori/brand tertentu (salah satu
 * eligible*Ids non-empty). Voucher tanpa scope berlaku untuk semua produk.
 */
export function voucherHasScope(voucher: VoucherEligibilityScope): boolean {
  return (
    (voucher.eligibleProductIds ?? []).length > 0 ||
    (voucher.eligibleCategoryIds ?? []).length > 0 ||
    (voucher.eligibleBrandIds ?? []).length > 0
  );
}

/**
 * True kalau voucher boleh dipakai untuk isi keranjang: TIDAK di-scope, ATAU
 * minimal SATU produk keranjang cocok ke scope-nya.
 *
 * Berbasis EKSISTENSI produk cocok (products.some) — BUKAN jumlah subtotal —
 * supaya produk cocok berharga 0 (hadiah / diskon 100%) tetap memenuhi scope.
 * Dipakai SEMUA surface (listing, checkout preview, order) supaya aturan scope
 * seragam untuk semua discountScope (termasuk gratis ongkir / SHIPPING).
 */
export function cartMatchesVoucherScope(
  voucher: VoucherEligibilityScope,
  products: EligibilityProductInput[]
): boolean {
  if (!voucherHasScope(voucher)) return true;
  return products.some((product) => voucherMatchesProduct(voucher, product));
}

/**
 * Batch-resolve brand id -> nama, untuk display voucher scoped ke brand
 * (mis. "Khusus Wolly+"). Dipakai oleh lib/voucher-list.ts dan
 * app/api/checkout/recalculate/route.ts -- satu tempat supaya query batch
 * (bukan N+1 per voucher) konsisten di semua caller.
 */
export async function loadBrandNamesByIds(
  brandIds: string[]
): Promise<Map<string, string>> {
  const uniqueIds = Array.from(new Set(brandIds));
  if (uniqueIds.length === 0) return new Map();
  const brands = await prisma.brand.findMany({
    where: { id: { in: uniqueIds } },
    select: { id: true, name: true },
  });
  return new Map(brands.map((b) => [b.id, b.name]));
}

/**
 * Format label display dari eligibleBrandIds voucher. null kalau voucher
 * tidak scoped ke brand manapun (termasuk kalau semua id-nya sudah tidak
 * ketemu lagi di brandNamesById, mis. brand dihapus).
 */
export function formatVoucherBrandName(
  eligibleBrandIds: string[],
  brandNamesById: Map<string, string>
): string | null {
  const names = eligibleBrandIds
    .map((id) => brandNamesById.get(id))
    .filter((name): name is string => Boolean(name));
  if (names.length === 0) return null;
  if (names.length === 1) return names[0];
  return `${names[0]} & ${names.length - 1} brand lain`;
}
