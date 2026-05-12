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

  // Checkout & sub-pages — fokus selesaikan transaksi
  /^\/checkout(\/|$)/,

  // Payment gateway — cegah user keluar dari flow bayar
  /^\/payment(\/|$)/,
  /^\/pembayaran(\/|$)/,

  // Auth flow — keyboard tidak ketabrakan nav + user fokus mengisi form
  /^\/member\/login(\/|$)/,
  /^\/member\/register(\/|$)/,
  /^\/member\/forgot-password(\/|$)/,
  /^\/member\/reset-password(\/|$)/,

  // Detail pesanan (tracking) — fokus pada status & info pengiriman
  /^\/member\/orders\/[^/]+$/,
  /^\/order-status\/[^/]+$/,
];

export function shouldHideBottomNav(pathname: string | null | undefined): boolean {
  if (!pathname) return false;
  return HIDDEN_BOTTOM_NAV_PATTERNS.some((pattern) => pattern.test(pathname));
}
