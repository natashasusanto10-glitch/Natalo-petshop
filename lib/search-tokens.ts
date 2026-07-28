/**
 * Tokenisasi query pencarian — dipakai bersama oleh search storefront
 * (lib/search.ts) DAN semua kotak cari admin (lib/admin-search.ts).
 *
 * Dipisah ke modul sendiri supaya helper murni ini bisa di-import tanpa
 * ikut menarik Meilisearch client + Prisma (lib/search.ts menarik keduanya).
 */

export function normalizeSearchText(value: string) {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function tokenizeSearchQuery(query: string) {
  return normalizeSearchText(query)
    .split(/\s+/)
    .map((token) => token.trim())
    .filter((token) => token.length >= 2);
}

/**
 * Bangun where clause AND-of-OR untuk daftar admin: query dipecah jadi
 * token, SETIAP token wajib muncul di salah satu field. Efeknya multi-kata
 * dengan urutan bebas ("santoso budi" ketemu "Budi Santoso") — beda dari
 * `contains` tunggal yang menuntut substring persis.
 *
 * `fieldsFor(token)` mengembalikan cabang OR untuk satu token.
 *
 * Kalau tokenisasi menghasilkan nol token (query 1 karakter seperti "5",
 * atau simbol saja), kita JATUH KEMBALI ke query mentah sebagai satu token.
 * Tanpa fallback ini pencarian "5" akan mengembalikan `undefined` → tidak
 * memfilter apa pun → admin melihat SELURUH daftar dan mengira filternya
 * rusak.
 */
export function tokenizedSearchWhere<T>(
  query: string,
  fieldsFor: (token: string) => T[],
): { AND: Array<{ OR: T[] }> } | undefined {
  const raw = query.trim();
  if (!raw) return undefined;

  const tokens = tokenizeSearchQuery(raw);
  const effective = tokens.length > 0 ? tokens : [raw];

  return { AND: effective.map((token) => ({ OR: fieldsFor(token) })) };
}
