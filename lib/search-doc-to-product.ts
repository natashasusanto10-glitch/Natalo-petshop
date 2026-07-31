import { normalizeProductWeight, type StoreProduct } from "@/lib/products";
import type { ProductSearchDoc } from "@/lib/search";

/**
 * Ubah dokumen search jadi bentuk yang dimengerti `ProductCard`.
 *
 * Dipakai `/products` supaya katalog tetap memakai kartu produk yang sama
 * dengan beranda, walau datanya kini datang dari `/api/search`.
 *
 * CATATAN: dokumen search tidak punya field video, jadi `videoUrl` selalu
 * kosong — kartu di `/products` jatuh ke gambar statis (diterima, spec §4.9).
 */
export function searchDocToStoreProduct(doc: ProductSearchDoc): StoreProduct {
  return {
    id: doc.id,
    name: doc.name,
    slug: doc.slug,
    description: doc.description,
    price: doc.price_min,
    discountPrice: doc.discount_price,
    memberPrice: doc.member_price,
    // `stock` dan `total_stock` di-set sama oleh productToSearchDoc; fallback
    // dipertahankan supaya dokumen lama/ganjil tidak bikin kartu "Habis" palsu.
    stock: doc.stock || doc.total_stock,
    // Dokumen search memakai berat mentah; samakan dengan /api/products supaya
    // berat yang ditulis ke keranjang (→ ongkir) tidak berbeda antar halaman.
    weightGram: normalizeProductWeight(doc.name, doc.slug, doc.weight_grams),
    imageUrl: doc.image_url,
    gallery: [],
    hasVariants: doc.has_variants,
    avgRating: doc.avg_rating,
    reviewCount: doc.review_count,
    categoryId: doc.category_id,
    categorySlug: doc.category_slug,
    brand: doc.brand_name,
    brandId: doc.brand_id,
  };
}
