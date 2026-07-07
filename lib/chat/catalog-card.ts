import type { StoreProduct } from "@/lib/products";

/**
 * Kartu produk customer-safe untuk Task 2 (staff share produk ke chat).
 * Allowlist ketat 9 field — TIDAK boleh bocorkan field internal
 * StoreProduct (mis. memberPrice, brandId, voucherPreview, soldCount).
 */
export type CatalogCard = {
  productId: string;
  slug: string;
  name: string;
  imageUrl: string | null;
  price: number;
  discountPrice: number | null;
  stock: number;
  isAvailable: boolean;
  brand: string | null;
};

/**
 * Proyeksi murni StoreProduct → CatalogCard. Pilih tiap field secara
 * eksplisit (bukan spread ...p) supaya tak ada field internal yang
 * ikut bocor ke response API.
 */
export function toCatalogCard(p: StoreProduct): CatalogCard {
  return {
    productId: p.id,
    slug: p.slug,
    name: p.name,
    imageUrl: p.imageUrl ?? null,
    price: p.price,
    discountPrice: p.discountPrice ?? null,
    stock: p.stock,
    isAvailable: p.stock > 0,
    brand: p.brand ?? null,
  };
}
