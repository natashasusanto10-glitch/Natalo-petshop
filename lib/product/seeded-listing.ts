/**
 * Gate jalur pengurutan berseed di getProducts (lib/products.ts).
 *
 * Kontrak dengan app: seed dikirim SELALU oleh halaman Produk, dan backend
 * mengabaikannya begitu ada filter apa pun — seed hanya untuk daftar
 * "Semua" yang polos. Fungsi ini adalah penjaga kontrak itu, dipisah ke
 * modul sendiri supaya bisa diuji tanpa menyeret Prisma.
 *
 * Dua pelajaran mahal yang dijaga test-nya:
 *
 * 1. `discountOnly` SEMPAT LUPA masuk gate. SQL berseed tidak punya syarat
 *    diskon, jadi `seed + discountOnly` yang lolos gate mengembalikan
 *    SELURUH katalog — halaman Flash Sale berisi shampoo dan pasir kucing.
 *    Bug ini tertidur lama karena tertutup kebetulan oleh inStock (lihat
 *    poin 2); terbukti hidup di produksi saat inStock dilepas dari gate.
 *
 * 2. `inStockOnly` sengaja TIDAK ada di sini. Dulu ia ikut menggagalkan
 *    gate — dan karena app SELALU mengirim inStock=true (default filter
 *    Flutter), seed tidak pernah aktif sama sekali: urutan katalog beku
 *    createdAt desc setiap hari. Sekarang filter stok diterapkan langsung
 *    di dalam SQL jalur berseed, bukan dengan mematikan jalurnya.
 */
export type SeededListingParams = {
  randomSeed?: string;
  category?: string;
  brand?: string;
  brands?: string[];
  search?: string;
  newFilter?: unknown;
  popularFilter?: unknown;
  excludeIds?: string[];
  hasPriceOnly?: boolean;
  withImageOnly?: boolean;
  discountOnly?: boolean;
};

export function canUseSeededListing(p: SeededListingParams): boolean {
  return Boolean(
    p.randomSeed &&
      !p.category &&
      !p.brand &&
      !p.brands?.length &&
      !p.search &&
      !p.newFilter &&
      !p.popularFilter &&
      !p.excludeIds?.length &&
      !p.hasPriceOnly &&
      !p.withImageOnly &&
      !p.discountOnly
  );
}
