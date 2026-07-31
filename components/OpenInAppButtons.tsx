"use client";

/**
 * Tombol "Buka di Aplikasi" + tautan store — dipakai halaman share publik
 * (/feed/<id>, /u/<username>) sebagai fallback web ala Shopee/Tokopedia.
 *
 * Kalau app ter-install, App Links (Android) / Universal Links (iOS) sudah
 * membuka app SEBELUM halaman ini sempat tampil. Halaman ini hanya terlihat
 * ketika app belum ter-install atau verifikasi link gagal di device tsb —
 * di situ tombol ini jadi jembatan:
 *
 * - Android: `intent://` URL memaksa OS resolve ke package app; kalau tidak
 *   ter-install, `S.browser_fallback_url` melempar ke Play Store. Ini pola
 *   yang dipakai Shopee/Tokopedia di halaman share mereka.
 * - iOS: tidak ada padanan intent://; andalkan Smart App Banner
 *   (`apple-itunes-app` di layout) + tautan App Store di bawah.
 *
 * ID App Store 6767888044 = satu-satunya sumber kebenaran (dari App Store
 * Connect, lihat app/layout.tsx). Jangan hardcode ID lain di halaman share.
 */

const ANDROID_PACKAGE = "com.natalo.petshop";
const APP_STORE_URL =
  "https://apps.apple.com/id/app/natalo-petshop/id6767888044";
const PLAY_STORE_URL = `https://play.google.com/store/apps/details?id=${ANDROID_PACKAGE}`;

function buildAndroidIntentUrl(path: string) {
  // intent:// membawa host+path tanpa scheme; scheme dideklarasikan di
  // parameter Intent. Fallback ke Play Store bila app tidak ter-install.
  const clean = path.startsWith("/") ? path : `/${path}`;
  return (
    `intent://www.natalopetshop.com${clean}` +
    `#Intent;scheme=https;package=${ANDROID_PACKAGE};` +
    `S.browser_fallback_url=${encodeURIComponent(PLAY_STORE_URL)};end`
  );
}

export default function OpenInAppButtons({ path }: { path: string }) {
  const openInApp = () => {
    const ua = navigator.userAgent || "";
    if (/android/i.test(ua)) {
      window.location.href = buildAndroidIntentUrl(path);
      return;
    }
    if (/iphone|ipad|ipod/i.test(ua)) {
      // Universal Link ke halaman ini sendiri — kalau app ter-install iOS
      // ambil alih; kalau tidak, jatuh ke App Store setelah jeda singkat.
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
    window.location.href = PLAY_STORE_URL;
  };

  return (
    <div className="mt-3 flex flex-wrap items-center gap-2">
      <button
        type="button"
        onClick={openInApp}
        className="rounded-full bg-blue-600 px-5 py-2 text-sm font-bold text-white hover:bg-blue-700"
      >
        Buka di Aplikasi
      </button>
      <a
        href={APP_STORE_URL}
        className="rounded-full border border-slate-300 px-4 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-50"
      >
        App Store
      </a>
      <a
        href={PLAY_STORE_URL}
        className="rounded-full border border-slate-300 px-4 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-50"
      >
        Google Play
      </a>
    </div>
  );
}
