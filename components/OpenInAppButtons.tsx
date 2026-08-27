"use client";

/**
 * Tombol "Buka di Aplikasi" + tautan store — dipakai halaman share publik
 * (/feed/<id>, /u/<username>) sebagai fallback web ala Shopee/Tokopedia.
 *
 * Kalau app ter-install, App Links (Android) / Universal Links (iOS) sudah
 * membuka app SEBELUM halaman ini sempat tampil. Halaman ini hanya terlihat
 * ketika app belum ter-install atau verifikasi link gagal di device tsb.
 *
 * Blok ini duduk di badan halaman (di bawah konten). Untuk layar kecil ada
 * juga StickyOpenInAppBar yang selalu terlihat — logika buka-app-nya SAMA,
 * dari components/open-in-app.ts.
 */

import { APP_STORE_URL, PLAY_STORE_URL, openInApp } from "./open-in-app";

export default function OpenInAppButtons({ path }: { path: string }) {
  return (
    <div className="mt-3 flex flex-wrap items-center gap-2">
      <button
        type="button"
        onClick={() => openInApp(path)}
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
