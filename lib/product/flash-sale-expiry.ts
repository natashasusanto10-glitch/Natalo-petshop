/**
 * Sisa harga Flash Sale yang sudah lewat.
 *
 * MASALAH YANG DITUTUP INI (ditemukan 2026-08-27): Flash Sale disimpan
 * sebagai dua kolom di Product — `discountPrice` (nominal) dan
 * `flashSaleEndsAt` (kapan berakhir). Ada DUA cara promo berakhir, dan
 * hanya satu yang bersih:
 *
 *   1. Diakhiri manual lewat tombol admin →
 *      POST /api/admin/flash-sale/end mengosongkan KEDUANYA. Bersih.
 *   2. Dibiarkan lewat waktu → TIDAK ADA yang mengosongkan apa pun.
 *      Tanggalnya sekadar berlalu; `discountPrice` menempel selamanya.
 *
 * Audit produksi menemukan 11 produk aktif dengan `discountPrice` terisi
 * dan NOL Flash Sale yang masih berjalan — semuanya jalur (2).
 *
 * Kenapa ini berbahaya, bukan sekadar kotor: halaman "Buat Flash Sale"
 * (app/admin/(protected)/diskon/flash-sale/new) memilih kandidat dengan
 * syarat `flashSaleEndsAt` null ATAU sudah lewat — jadi kesebelas produk
 * itu MUNCUL sebagai kandidat lengkap dengan harga diskon lama yang masih
 * menempel. Begitu ada yang mengisi tanggal baru tanpa menyentuh harganya,
 * produk-produk itu langsung menyala di diskon 29–40% tanpa disengaja.
 * Salah satunya Royal Canin turun 40%.
 *
 * Pelanggan sendiri tidak pernah melihat diskon hantu ini: sisi storefront
 * memakai `resolveActiveDiscount` (lib/product-pricing.ts) yang selalu
 * memeriksa tanggalnya juga. Yang tertipu hanya panel admin, yang membaca
 * `discountPrice` mentah.
 *
 * KENAPA HANYA `discountPrice` YANG DIKOSONGKAN, BUKAN JUGA
 * `flashSaleEndsAt`: tanggal itu satu-satunya jejak riwayat promo.
 * Halaman /admin/diskon/flash-sale menampilkan Flash Sale lampau
 * (7/30 hari terakhir) dengan mengurutkan `flashSaleEndsAt`, dan
 * menghitung "Total pernah flash sale" dari `flashSaleEndsAt: { not: null }`.
 * Menghapusnya = riwayatnya lenyap. Halaman itu sudah menangani
 * `discountPrice` null dengan benar (jatuh ke harga normal, tanpa badge %),
 * jadi mengosongkan nominal saja aman.
 */
import type { Prisma } from "@prisma/client";

/**
 * Produk yang masih menyimpan `discountPrice` padahal Flash Sale-nya
 * tidak lagi berjalan.
 *
 * Termasuk `flashSaleEndsAt: null` — itu bentuk paling parah dari sisa
 * yang sama: nominal diskon tanpa tanggal apa pun, tidak akan pernah
 * kedaluwarsa sendiri dan tidak terlihat di halaman riwayat Flash Sale.
 */
export function expiredFlashSaleWhere(now: Date = new Date()): Prisma.ProductWhereInput {
  return {
    discountPrice: { not: null },
    OR: [{ flashSaleEndsAt: null }, { flashSaleEndsAt: { lte: now } }],
  };
}
