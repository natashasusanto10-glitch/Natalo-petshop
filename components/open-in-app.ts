/**
 * Logika "buka di aplikasi" bersama — dipakai OpenInAppButtons (blok tombol
 * di badan halaman, semua layar) dan StickyOpenInAppBar (bar melekat bawah,
 * layar kecil saja). Satu implementasi supaya dua pintu itu tidak pernah
 * berbeda perilaku.
 *
 * ID App Store 6767888044 = satu-satunya sumber kebenaran (dari App Store
 * Connect, lihat app/layout.tsx). Jangan hardcode ID lain di halaman share.
 */

export const ANDROID_PACKAGE = "com.natalo.petshop";
export const APP_STORE_URL =
  "https://apps.apple.com/id/app/natalo-petshop/id6767888044";
export const PLAY_STORE_URL = `https://play.google.com/store/apps/details?id=${ANDROID_PACKAGE}`;

export function buildAndroidIntentUrl(path: string) {
  // intent:// membawa host+path tanpa scheme; scheme dideklarasikan di
  // parameter Intent. Fallback ke Play Store bila app tidak ter-install.
  const clean = path.startsWith("/") ? path : `/${path}`;
  return (
    `intent://www.natalopetshop.com${clean}` +
    `#Intent;scheme=https;package=${ANDROID_PACKAGE};` +
    `S.browser_fallback_url=${encodeURIComponent(PLAY_STORE_URL)};end`
  );
}

/**
 * Toko yang tepat untuk platform yang tidak bisa membuka app-nya sendiri
 * (desktop). Dulu SEMUA non-Android non-iOS dilempar ke Play Store —
 * pengguna Mac yang menekan "Buka di Aplikasi" mendarat di toko yang
 * salah.
 */
export function desktopStoreUrl(userAgent: string) {
  return /mac/i.test(userAgent) ? APP_STORE_URL : PLAY_STORE_URL;
}

/**
 * Buka `path` di app kalau ter-install; kalau tidak, ke store yang sesuai.
 *
 * - Android: intent:// memaksa OS resolve ke package app; tidak
 *   ter-install -> S.browser_fallback_url melempar ke Play Store.
 *   Pola yang dipakai Shopee/Tokopedia di halaman share mereka.
 * - iOS: tidak ada padanan intent://; coba Universal Link ke halaman ini
 *   sendiri — app ter-install mengambil alih; kalau tidak, jatuh ke App
 *   Store setelah jeda singkat. `pagehide` membatalkan fallback saat app
 *   benar-benar terbuka.
 * - Desktop: langsung ke store sesuai OS (lihat desktopStoreUrl).
 */
export function openInApp(path: string) {
  const ua = navigator.userAgent || "";
  if (/android/i.test(ua)) {
    window.location.href = buildAndroidIntentUrl(path);
    return;
  }
  if (/iphone|ipad|ipod/i.test(ua)) {
    const fallback = window.setTimeout(() => {
      window.location.href = APP_STORE_URL;
    }, 1200);
    window.addEventListener(
      "pagehide",
      () => window.clearTimeout(fallback),
      { once: true },
    );
    window.location.href = `https://www.natalopetshop.com${path}`;
    return;
  }
  window.location.href = desktopStoreUrl(ua);
}
