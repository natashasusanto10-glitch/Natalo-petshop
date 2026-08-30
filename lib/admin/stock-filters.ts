/**
 * Filter halaman Stok admin.
 *
 * CATATAN PENTING soal `Product.stock` pada produk bervarian — mudah salah
 * paham, dan aku sendiri sempat salah:
 *
 * Form admin memang menulis stok induk sebagai 0 saat produk punya varian
 * (`ProductForm.tsx`: `stock: effective ? 0 : ...`). TAPI angka itu langsung
 * ditimpa: setiap jalur yang menyentuh varian (`/api/admin/products`,
 * `.../[id]/variants`, `.../variants/bulk`, pembuatan & pembatalan pesanan)
 * menghitung ulang `Product.stock` sebagai JUMLAH stok varian yang aktif dan
 * belum terhapus. Jadi `Product.stock` adalah agregat yang terpelihara, dan
 * `stock: 0` pada produk bervarian benar-benar berarti semua variannya habis.
 *
 * Karena itu filter berbasis stok induk TIDAK perlu mengecualikan produk
 * bervarian. Yang tidak bisa dijawab stok induk hanyalah "varian yang MANA
 * yang menipis" — untuk itu ada `variantStockWhere` dan tab varian tersendiri.
 */

/** Ambang "menipis". Sengaja satu tempat — dashboard memakai angka yang sama. */
export const LOW_STOCK_LIMIT = 5;

export type StockFilter = "semua" | "menipis" | "habis";

export function parseStockFilter(raw: string | undefined): StockFilter {
  return raw === "menipis" || raw === "habis" ? raw : "semua";
}

export type StockTab = "produk" | "varian";

export function parseStockTab(raw: string | undefined): StockTab {
  return raw === "varian" ? "varian" : "produk";
}

/** Rentang stok untuk satu filter, atau `undefined` kalau "semua". */
function stockRange(filter: StockFilter) {
  if (filter === "habis") return { lte: 0 };
  if (filter === "menipis") return { gt: 0, lte: LOW_STOCK_LIMIT };
  return undefined;
}

/**
 * Produk aktif menurut stok induknya — yang untuk produk bervarian adalah
 * jumlah stok seluruh variannya (lihat catatan di atas berkas ini).
 */
export function productStockWhere(filter: StockFilter) {
  const range = stockRange(filter);
  return {
    isActive: true,
    ...(range ? { stock: range } : {}),
  };
}

/**
 * Varian aktif dari produk aktif. Varian terhapus lunak tidak dihitung —
 * sama dengan yang dipakai saat menghitung ulang agregat stok induk.
 */
export function variantStockWhere(filter: StockFilter) {
  const range = stockRange(filter);
  return {
    isActive: true,
    deletedAt: null,
    product: { isActive: true },
    ...(range ? { stock: range } : {}),
  };
}

/** Label + warna satu angka stok. Dipakai baris produk maupun varian. */
export function stockTone(stock: number): {
  label: string;
  badge: "danger" | "warning" | "success";
} {
  if (stock <= 0) return { label: "Habis", badge: "danger" };
  if (stock <= LOW_STOCK_LIMIT) return { label: "Menipis", badge: "warning" };
  return { label: "Tersedia", badge: "success" };
}

/**
 * Apakah produk hasil impor layak tampil di toko?
 *
 * Importer adalah SATU-SATUNYA jalur tulis yang TIDAK menghitung ulang agregat
 * stok induk dari varian yang dibuatnya — ia menulis `stock` apa adanya dari
 * payload. Jadi kalau suatu payload mengirim produk bervarian dengan stok
 * induk 0 (dan stok sesungguhnya hanya di tiap varian), aturan lama
 * `isActive: stock > 0` akan menonaktifkan produk itu dari toko diam-diam.
 *
 * Fungsi ini menutup celah itu tanpa mengubah perilaku untuk payload yang
 * sudah benar: kalau variannya tidak ikut dikirim, penilaiannya kembali ke
 * stok induk persis seperti sebelumnya.
 */
export function importedProductIsActive(product: {
  hasVariants: boolean;
  stock: number;
  variants: Array<{ stock: number }>;
}): boolean {
  if (product.hasVariants && product.variants.length > 0) {
    return product.variants.some((v) => v.stock > 0);
  }
  return product.stock > 0;
}
