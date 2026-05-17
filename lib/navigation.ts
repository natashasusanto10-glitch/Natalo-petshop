/**
 * Pattern route yang harus menyembunyikan bottom navigation.
 *
 * Tujuan: kasih halaman fokus penuh (detail produk, checkout, auth, detail
 * order) tanpa godaan tab pindah. Mirip pola Tokopedia/Shopee — main tab
 * punya bottom nav, sub-page (detail, transactional) tidak.
 *
 * Logic terpusat di sini supaya:
 * - BottomNavigation.tsx hanya call `shouldHideBottomNav(pathname)`
 * - CSS / layout bisa baca body[data-bottom-nav="hidden"] untuk adjust padding
 * - Tambah route baru = tambah satu baris di array bawah
 */
export const HIDDEN_BOTTOM_NAV_PATTERNS: RegExp[] = [
  // Detail produk — fokus konversi, diganti sticky bottom CTA
  /^\/products\/[^/]+$/,
  /^\/search(\/|$)/,

  // Keranjang — task-focused flow menuju checkout, tanpa bottom tab distraction
  /^\/cart$/,

  // Checkout & sub-pages — fokus selesaikan transaksi
  /^\/checkout(\/|$)/,

  // Inner pages — navigasi balik ada di sticky page title, bukan bottom tab
  /^\/tentang-kami(\/|$)/,
  /^\/cara-pemesanan(\/|$)/,
  /^\/syarat-ketentuan(\/|$)/,
  /^\/kebijakan-privasi(\/|$)/,
  /^\/kebijakan-pengembalian(\/|$)/,
  /^\/bantuan(\/|$)/,
  /^\/help(\/|$)/,
  /^\/wishlist(\/|$)/,
  /^\/member\/favorites(\/|$)/,
  /^\/member\/points(\/|$)/,
  /^\/member\/reviews(\/|$)/,
  /^\/member\/vouchers(\/|$)/,
  /^\/account\/loyalty\/redeem$/,
  /^\/notifications(\/|$)/,
  /^\/akun\/alamat(\/|$)/,
  /^\/akun\/postingan-saya(\/|$)/,
  /^\/akun\/sesi-aktif(\/|$)/,
  /^\/akun\/pengaturan(\/|$)/,
  /^\/akun\/hapus-akun(\/|$)/,
  /^\/addresses(\/|$)/,
  /^\/brands(\/|$)/,

  // Payment gateway — cegah user keluar dari flow bayar
  /^\/payment(\/|$)/,
  /^\/pembayaran(\/|$)/,

  // Auth flow — keyboard tidak ketabrakan nav + user fokus mengisi form
  /^\/member\/login(\/|$)/,
  /^\/member\/register(\/|$)/,
  /^\/member\/forgot-password(\/|$)/,
  /^\/member\/reset-password(\/|$)/,

  // Detail pesanan (tracking) — fokus pada status & info pengiriman
  /^\/member\/orders$/,
  /^\/member\/orders\/[^/]+$/,
  /^\/member\/profile$/,
  /^\/account\/settings(\/|$)/,
  /^\/account\/profile(\/|$)/,
  /^\/order-status(\/|$)/,
  /^\/pesanan\/[^/]+$/,
  /^\/pesanan\/[^/]+\/success$/,

  // Feed upload flow — full-screen immersive video posting (Pilih → Preview
  // → Trim → Detail → Menunggu Review). Bottom nav harus hilang supaya flow
  // tidak bocor visual ke layar di belakang.
  /^\/feed\/upload(\/|$)/,

  // Review/rating form aliases — fokus mengisi rating dan ulasan produk
  /^\/review(\/|$)/,
  /^\/reviews(\/|$)/,
  /^\/rating(\/|$)/,
  /^\/order\/review(\/|$)/,
  /^\/product\/review(\/|$)/,
  /^\/write-review(\/|$)/,
];

export function shouldHideBottomNav(
  pathname: string | null | undefined
): boolean {
  if (!pathname) return false;
  return HIDDEN_BOTTOM_NAV_PATTERNS.some((pattern) => pattern.test(pathname));
}
