"use client";

/**
 * Bar "Buka di aplikasi" melekat di bawah layar — gaya Shopee/Tokopedia —
 * untuk halaman share publik (/feed/<id>, /u/<username>).
 *
 * Kenapa perlu, padahal OpenInAppButtons sudah ada: blok tombol itu duduk
 * di BAWAH konten. Di layar HP, poster 9:16 saja sudah menghabiskan hampir
 * seluruh layar, jadi tombolnya praktis selalu di bawah lipatan — harus
 * digulir dulu untuk ketemu. Bar ini selalu terlihat tanpa memaksa.
 *
 * Keputusan desain (disetujui lewat mockup):
 * - Layar kecil saja (`md:hidden`) — di desktop bar bawah tidak masuk
 *   akal; blok tombol yang lama tetap ada untuk itu.
 * - Bisa ditutup, tapi menutup MENYUSUTKAN jadi pil kecil di pojok, bukan
 *   menghilangkan: orang yang menutup karena refleks tetap punya jalan ke
 *   app tanpa harus menggulir. Pilihannya diingat per-sesi (sessionStorage)
 *   supaya navigasi antar postingan tidak memunculkan bar lagi.
 * - `pb-[env(safe-area-inset-bottom)]` menjaga tombol dari area home
 *   indicator iPhone.
 *
 * Smart App Banner iOS (`apple-itunes-app`) SENGAJA dimatikan di halaman
 * yang memakai bar ini (lihat metadata.other di share-metadata.ts /
 * profile-share-data.ts) — tanpa itu iPhone dapat dua ajakan sekaligus,
 * banner Safari di atas + bar ini di bawah.
 */

import { useEffect, useState } from "react";

import { openInApp } from "./open-in-app";

const DISMISS_KEY = "natalo-open-in-app-bar-dismissed";

export default function StickyOpenInAppBar({ path }: { path: string }) {
  // Mulai dari null (tidak render apa pun) sampai preferensi sesi terbaca —
  // kalau mulai dari "bar tampil", pengguna yang sudah menutupnya melihat
  // bar berkedip sesaat di tiap halaman.
  const [dismissed, setDismissed] = useState<boolean | null>(null);

  useEffect(() => {
    try {
      setDismissed(sessionStorage.getItem(DISMISS_KEY) === "1");
    } catch {
      // sessionStorage bisa terlarang (mis. mode privat lama) — tampilkan
      // bar; paling buruk pilihan tutup tidak diingat antar halaman.
      setDismissed(false);
    }
  }, []);

  const dismiss = () => {
    setDismissed(true);
    try {
      sessionStorage.setItem(DISMISS_KEY, "1");
    } catch {
      // Tidak apa-apa — pilihan hanya berlaku untuk halaman ini.
    }
  };

  if (dismissed === null) return null;

  if (dismissed) {
    return (
      <div className="fixed bottom-0 right-0 z-40 p-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] md:hidden">
        <button
          type="button"
          onClick={() => openInApp(path)}
          className="flex items-center gap-1.5 rounded-full bg-blue-600 px-4 py-2 text-xs font-bold text-white shadow-lg hover:bg-blue-700"
        >
          Buka di app
        </button>
      </div>
    );
  }

  return (
    <div className="fixed inset-x-0 bottom-0 z-40 border-t border-slate-200 bg-white px-3 pt-2.5 pb-[calc(0.625rem+env(safe-area-inset-bottom))] md:hidden">
      <div className="flex items-center gap-3">
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-blue-600 text-base font-black text-white">
          N
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-bold leading-tight text-slate-900">
            Natalo Petshop
          </p>
          <p className="truncate text-xs leading-tight text-slate-500">
            Buka postingan ini di aplikasi
          </p>
        </div>
        <button
          type="button"
          onClick={() => openInApp(path)}
          className="shrink-0 rounded-full bg-blue-600 px-5 py-2 text-sm font-bold text-white hover:bg-blue-700"
        >
          Buka
        </button>
        <button
          type="button"
          onClick={dismiss}
          aria-label="Tutup"
          className="shrink-0 p-1 text-slate-400 hover:text-slate-600"
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true">
            <path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
          </svg>
        </button>
      </div>
    </div>
  );
}
