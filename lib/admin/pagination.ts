/**
 * Pembacaan nomor halaman dari query string.
 *
 * GOTCHA yang jadi alasan modul ini ada: `Math.max(1, parseInt("abc", 10))`
 * TIDAK menghasilkan 1 — ia menghasilkan `NaN`, karena `Math.max` mengembalikan
 * `NaN` begitu salah satu argumennya `NaN`. Nilai itu lalu mengalir ke
 * `skip: (page - 1) * PAGE_SIZE`, dan Prisma menolak `skip` non-bilangan
 * dengan melempar — halaman admin balas 500 hanya karena `?page=abc`.
 * Cukup satu tautan rusak atau bookmark basi untuk memicunya.
 */

/** Nomor halaman ≥ 1. Apa pun yang tidak masuk akal jatuh ke 1, bukan melempar. */
export function parsePageParam(raw: string | string[] | undefined): number {
  const value = Array.isArray(raw) ? raw[0] : raw;
  const parsed = Number.parseInt(value ?? "", 10);
  if (!Number.isFinite(parsed) || parsed < 1) return 1;
  // Batas atas menjaga `skip` tetap bilangan bulat yang aman; tanpa ini
  // `?page=9e99` masih bisa membuat Prisma melempar.
  return Math.min(parsed, Number.MAX_SAFE_INTEGER);
}

/** Batas jumlah baris ≥ 1, dijepit ke `max`. Nilai tak masuk akal → `fallback`. */
export function parseLimitParam(
  raw: string | string[] | undefined,
  fallback: number,
  max: number,
): number {
  const value = Array.isArray(raw) ? raw[0] : raw;
  const parsed = Number.parseInt(value ?? "", 10);
  if (!Number.isFinite(parsed) || parsed < 1) return fallback;
  return Math.min(parsed, max);
}
