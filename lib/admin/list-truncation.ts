/**
 * Pesan "menampilkan N dari M" untuk daftar admin yang dibatasi `take`.
 *
 * Masalah yang dipecahkan: beberapa halaman admin memakai `take: 100` tanpa
 * memberi tahu apa pun. Kalau data melewati batas itu, sisanya hilang DIAM-DIAM
 * — admin mengira daftar sudah lengkap padahal tidak. Kehilangan yang tidak
 * terlihat lebih berbahaya daripada daftar yang jujur mengaku terpotong.
 *
 * `total` WAJIB dihitung dengan `where` yang SAMA PERSIS dengan query daftarnya.
 * Kalau tidak, angkanya berbohong dengan cara baru.
 */
export type ListCountNotice =
  | { kind: "empty" }
  | { kind: "complete"; text: string }
  | { kind: "truncated"; text: string; hiddenCount: number };

const NUMBER_ID = new Intl.NumberFormat("id-ID");

export function listCountNotice(
  shown: number,
  total: number,
  noun: string,
): ListCountNotice {
  // Pertahanan terhadap hitung negatif / NaN dari pemanggil.
  const safeShown = Number.isFinite(shown) ? Math.max(0, Math.trunc(shown)) : 0;
  const safeTotalRaw = Number.isFinite(total) ? Math.max(0, Math.trunc(total)) : 0;
  // `total` dihitung di query terpisah, jadi bisa tertinggal dari `shown` kalau
  // ada penulisan data di antara keduanya. Jangan pernah lapor angka tersembunyi
  // negatif — anggap saja daftarnya lengkap.
  const safeTotal = Math.max(safeShown, safeTotalRaw);

  if (safeTotal === 0) return { kind: "empty" };

  if (safeShown >= safeTotal) {
    return { kind: "complete", text: `${NUMBER_ID.format(safeTotal)} ${noun}` };
  }

  const hiddenCount = safeTotal - safeShown;
  return {
    kind: "truncated",
    hiddenCount,
    text: `Menampilkan ${NUMBER_ID.format(safeShown)} dari ${NUMBER_ID.format(
      safeTotal,
    )} ${noun} — ${NUMBER_ID.format(
      hiddenCount,
    )} lainnya belum tampil. Persempit filter atau pencarian.`,
  };
}
