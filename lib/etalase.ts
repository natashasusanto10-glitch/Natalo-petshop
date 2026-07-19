// Pure copy helpers for the "Etalase Natalo" band header.
// No data access — callers pass resolved names. Keeps band text consistent
// across /products, /kategori, /brands, /search.

export const ETALASE_TRUST = [
  "Kirim hari ini se-Medan",
  "100% Original",
  "Toko fisik sejak 2018",
] as const;

// Owner-confirmed store rating. Single source of truth — change here only.
export const NATALO_RATING = "4.9";

type HeadingOpts = {
  brandName?: string | null;
  categoryName?: string | null;
  isSearch?: boolean;
  query?: string | null;
};

export function etalaseHeading({
  brandName,
  categoryName,
  isSearch,
  query,
}: HeadingOpts): string {
  if (isSearch && query && query.trim()) return `Hasil untuk "${query.trim()}"`;
  if (brandName && brandName.trim()) return `Produk ${brandName.trim()}`;
  if (categoryName && categoryName.trim()) return categoryName.trim();
  return "Katalog Produk";
}

type TaglineOpts = {
  brandName?: string | null;
  categoryName?: string | null;
  isSearch?: boolean;
};

export function etalaseTagline({
  brandName,
  categoryName,
  isSearch,
}: TaglineOpts): string {
  if (isSearch) return "Menampilkan produk yang cocok dengan pencarianmu.";
  if (brandName && brandName.trim())
    return `Koleksi ${brandName.trim()} original, siap kirim dari toko kami di Medan.`;
  if (categoryName && categoryName.trim())
    return `Pilihan ${categoryName.trim()} lengkap, langsung dari rak Natalo.`;
  return "Semua kebutuhan hewan & aquarium, langsung dari toko kami di Medan.";
}
