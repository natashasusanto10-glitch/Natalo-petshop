/**
 * Kotak cari daftar admin — satu sumber kebenaran untuk field apa saja yang
 * ikut dicari per entitas.
 *
 * Kenapa dipisah: daftar field-nya semula hidup DI DALAM masing-masing route
 * API. Saat halaman admin ikut punya kotak cari, daftar itu akan tersalin ke
 * tempat kedua — dan dua salinan pasti melenceng cepat atau lambat (satu sisi
 * menambah "cari via email", sisi lain tidak, lalu hasil pencarian yang sama
 * berbeda tergantung dari mana admin mencarinya). Halaman dan API sekarang
 * memanggil fungsi yang sama persis.
 *
 * Semua fungsi mengembalikan `{ AND: [...] }` atau `undefined` (query kosong).
 * PENTING: hasilnya masuk ke `where.AND`, JANGAN digabung ke `where.OR` milik
 * filter status — kalau digabung, baris yang cocok namanya akan lolos walau
 * statusnya tidak cocok (bug yang pernah terjadi di daftar voucher).
 */
import { tokenizedSearchWhere } from "./search-tokens";

const insensitive = "insensitive" as const;

/**
 * Pesanan: nomor pesanan, nama pembeli, nomor HP.
 *
 * `customerPhone` sengaja TANPA `mode: insensitive` — nomor telepon tidak
 * punya huruf, dan Postgres tak bisa memakai index biasa untuk ILIKE.
 */
export function orderSearchWhere(query: string) {
  return tokenizedSearchWhere(query, (token) => [
    { orderNumber: { contains: token, mode: insensitive } },
    { customerName: { contains: token, mode: insensitive } },
    { customerPhone: { contains: token } },
  ]);
}

/** Customer: nama, email, nomor HP, username. */
export function customerSearchWhere(query: string) {
  return tokenizedSearchWhere(query, (token) => [
    { name: { contains: token, mode: insensitive } },
    { email: { contains: token, mode: insensitive } },
    { phone: { contains: token } },
    { username: { contains: token, mode: insensitive } },
  ]);
}

/** Ulasan: judul, isi, nama produk yang diulas. */
export function reviewSearchWhere(query: string) {
  return tokenizedSearchWhere(query, (token) => [
    { title: { contains: token, mode: insensitive } },
    { content: { contains: token, mode: insensitive } },
    { product: { name: { contains: token, mode: insensitive } } },
  ]);
}

/** Voucher: kode dan nama campaign. */
export function voucherSearchWhere(query: string) {
  return tokenizedSearchWhere(query, (token) => [
    { code: { contains: token, mode: insensitive } },
    { name: { contains: token, mode: insensitive } },
  ]);
}
