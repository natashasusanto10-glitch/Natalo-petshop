/**
 * Filter halaman Stok admin.
 *
 * KENAPA PRODUK BERVARIAN DIPISAH — bukan sekadar rapi-rapi:
 * saat sebuah produk punya varian, form admin menulis stok INDUKNYA sebagai 0
 * (`ProductForm.tsx`: `stock: effective ? 0 : ...`) karena stok yang asli
 * hidup di `ProductVariant.stock`. Akibatnya query `stock: 0` menandai SETIAP
 * produk bervarian sebagai "Habis", betapa pun penuh gudangnya. Angka itu
 * tidak salah sedikit — ia salah untuk seluruh kelas produk.
 *
 * Jadi baris berbasis stok induk HARUS dibatasi `hasVariants: false`, dan stok
 * varian dihitung dari tabel varian.
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
  if (filter === "habis") return { equals: 0 };
  if (filter === "menipis") return { gt: 0, lte: LOW_STOCK_LIMIT };
  return undefined;
}

/**
 * Produk yang stok induknya BERMAKNA — yaitu yang tidak punya varian.
 * `hasVariants: false` bukan pilihan gaya; tanpa itu angkanya bohong.
 */
export function productStockWhere(filter: StockFilter) {
  const range = stockRange(filter);
  return {
    isActive: true,
    hasVariants: false,
    ...(range ? { stock: range } : {}),
  };
}

/** Varian aktif dari produk aktif. Varian terhapus lunak tidak dihitung. */
export function variantStockWhere(filter: StockFilter) {
  const range = stockRange(filter);
  return {
    isActive: true,
    deletedAt: null,
    product: { isActive: true },
    ...(range ? { stock: range } : {}),
  };
}

/**
 * "Masih ada stok" untuk daftar produk GABUNGAN (varian dan non-varian
 * bercampur), seperti /admin/products.
 *
 * Beda dengan `productStockWhere` di atas: di sana produk bervarian memang
 * dikeluarkan karena halaman Stok memberi mereka tab sendiri. Di daftar produk
 * utama, mengeluarkan mereka berarti produk bervarian lenyap dari tab
 * "Tersedia" MAUPUN "Habis" — jadi di sini stoknya dinilai lewat variannya.
 */
export function productInStockWhere() {
  return {
    OR: [
      { hasVariants: false, stock: { gt: 0 } },
      {
        hasVariants: true,
        variants: {
          some: { isActive: true, deletedAt: null, stock: { gt: 0 } },
        },
      },
    ],
  };
}

/**
 * Kebalikannya: tidak ada satu pun stok yang bisa dijual.
 * `none` mencakup produk bervarian yang seluruh variannya habis ATAU yang
 * variannya sudah terhapus semua.
 */
export function productOutOfStockWhere() {
  return {
    OR: [
      { hasVariants: false, stock: { lte: 0 } },
      {
        hasVariants: true,
        variants: {
          none: { isActive: true, deletedAt: null, stock: { gt: 0 } },
        },
      },
    ],
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
