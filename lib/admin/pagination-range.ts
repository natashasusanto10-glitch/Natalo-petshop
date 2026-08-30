/**
 * Deret nomor halaman untuk paginasi admin.
 *
 * Kenapa tidak menampilkan semua nomor: katalog produk sudah 29 halaman dan
 * akan terus tumbuh. Deretan 29 angka justru jadi keramaian baru — persoalan
 * yang sama dengan daftar yang terlalu panjang, hanya pindah tempat.
 *
 * Bentuknya: selalu halaman pertama & terakhir, ditambah beberapa tetangga di
 * kiri-kanan halaman aktif, dan "…" untuk lompatan. Lebarnya TETAP berapa pun
 * jumlah halamannya, jadi tombolnya tidak berpindah-pindah posisi saat admin
 * mengklik berurutan.
 */
export type PageSlot = number | "gap";

/**
 * @param siblings jumlah tetangga di tiap sisi halaman aktif.
 */
export function paginationRange(
  current: number,
  total: number,
  siblings = 1,
): PageSlot[] {
  if (!Number.isFinite(total) || total < 1) return [];
  const safeCurrent = Math.min(Math.max(1, Math.trunc(current) || 1), total);
  const safeSiblings = Math.max(0, Math.trunc(siblings) || 0);

  // Ambang: kalau semua nomor muat tanpa "…", tampilkan semuanya. Angkanya =
  // pertama + terakhir + aktif + tetangga kiri-kanan + dua slot "…".
  const maxSlots = safeSiblings * 2 + 5;
  if (total <= maxSlots) {
    return Array.from({ length: total }, (_, i) => i + 1);
  }

  const left = Math.max(safeCurrent - safeSiblings, 1);
  const right = Math.min(safeCurrent + safeSiblings, total);
  const showLeftGap = left > 2;
  const showRightGap = right < total - 1;

  // Saat berada di dekat salah satu ujung, deret digeser ke sisi itu supaya
  // jumlah tombolnya tetap sama — bukan menyusut jadi "1 2 3 … 29".
  if (!showLeftGap && showRightGap) {
    const count = safeSiblings * 2 + 3;
    return [
      ...Array.from({ length: Math.min(count, total - 1) }, (_, i) => i + 1),
      "gap",
      total,
    ];
  }

  if (showLeftGap && !showRightGap) {
    const count = safeSiblings * 2 + 3;
    const start = Math.max(total - count + 1, 2);
    return [
      1,
      "gap",
      ...Array.from({ length: total - start + 1 }, (_, i) => start + i),
    ];
  }

  return [
    1,
    "gap",
    ...Array.from({ length: right - left + 1 }, (_, i) => left + i),
    "gap",
    total,
  ];
}
