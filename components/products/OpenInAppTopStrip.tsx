"use client";

/**
 * Strip tipis "Lebih mudah di aplikasi" di ATAS konten halaman produk —
 * layar kecil saja.
 *
 * Kenapa bukan StickyOpenInAppBar seperti halaman feed/profil: halaman
 * produk SUDAH punya bar melekat di bawah (Chat + Keranjang). Dua bar
 * bertumpuk memakan tinggi layar dan mendorong tombol Keranjang menjauh dari
 * jempol. Strip di atas adalah hal pertama yang terlihat, tidak menyentuh bar
 * belanja, dan bisa ditutup (dipilih user lewat mockup: Opsi A).
 *
 * Kenapa perlu sama sekali: link produk adalah yang paling sering dibagikan,
 * tapi sampai sekarang halaman produk TIDAK punya ajakan buka/unduh app —
 * hanya Smart App Banner Safari, yang tidak muncul di browser dalam WhatsApp
 * (tempat kebanyakan link dibuka). Orang tanpa app mendarat di web tanpa
 * pernah diberi tahu app-nya ada.
 *
 * Logika buka-app SAMA dengan feed/profil (components/open-in-app.ts): app
 * terpasang → langsung ke produk ini; tidak → App Store / Play Store.
 * Pilihan tutup diingat per-sesi supaya berpindah antar produk tidak
 * memunculkannya lagi. Kunci sessionStorage DIBEDAKAN dari bar feed: menutup
 * bar di postingan tidak seharusnya ikut menyembunyikan strip di produk.
 */

import { useEffect, useState } from "react";

import { openInApp } from "../open-in-app";

const DISMISS_KEY = "natalo-open-in-app-strip-dismissed";

export default function OpenInAppTopStrip({ path }: { path: string }) {
  // null = belum tahu preferensi sesi; jangan render dulu supaya pengguna
  // yang sudah menutup tidak melihat strip berkedip sesaat.
  const [dismissed, setDismissed] = useState<boolean | null>(null);

  useEffect(() => {
    try {
      setDismissed(sessionStorage.getItem(DISMISS_KEY) === "1");
    } catch {
      setDismissed(false);
    }
  }, []);

  if (dismissed !== false) return null;

  const dismiss = () => {
    setDismissed(true);
    try {
      sessionStorage.setItem(DISMISS_KEY, "1");
    } catch {
      // Pilihan hanya berlaku untuk halaman ini — tidak apa-apa.
    }
  };

  return (
    <div
      role="complementary"
      aria-label="Buka di aplikasi Natalo"
      className="flex items-center gap-2.5 border-b border-blue-100 bg-blue-50 px-3 py-2 md:hidden"
    >
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-natalo-600 text-sm font-black text-white">
        N
      </div>
      <div className="min-w-0 flex-1">
        <p className="text-[13px] font-bold leading-tight text-natalo-800">
          Lebih mudah di aplikasi Natalo
        </p>
        <p className="truncate text-[11px] leading-tight text-natalo-700">
          Voucher, poin, dan pelacakan pesanan
        </p>
      </div>
      <button
        type="button"
        onClick={() => openInApp(path)}
        className="shrink-0 rounded-full bg-natalo-600 px-4 py-1.5 text-xs font-bold text-white hover:bg-natalo-700"
      >
        Buka
      </button>
      <button
        type="button"
        onClick={dismiss}
        aria-label="Tutup"
        className="shrink-0 p-1 text-slate-400 hover:text-slate-600"
      >
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
        </svg>
      </button>
    </div>
  );
}
