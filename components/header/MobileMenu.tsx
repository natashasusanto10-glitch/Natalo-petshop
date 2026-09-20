"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { usePathname } from "next/navigation";
import {
  readCategoryCache,
  writeCategoryCache,
  isCategoryCacheFresh,
  type CachedCategorySummary,
} from "@/lib/client-performance";

const STATIC_LINKS = [
  { href: "/products", label: "Semua Produk" },
  { href: "/brands", label: "Brand" },
  { href: "/products?sort=promo", label: "Promo" },
  { href: "/products?sort=terlaris", label: "Terlaris" },
  { href: "/products?sort=baru", label: "Produk Baru" },
  { href: "/feed", label: "Feed" },
];

const STORE_ADDRESS = "JLN MT Haryono No 103 B C D, Medan";
const MAPS_HREF = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
  `${STORE_ADDRESS} Natalo Petshop`,
)}`;

/**
 * Menu mobile (hamburger) — drawer geser dari kiri. Isi: daftar kategori
 * (cache localStorage + /api/categories, pola sama dengan
 * DesktopCategoryNav), tautan jelajah, dan kontak toko (WhatsApp + peta).
 *
 * Layer: backdrop z-[1900] / panel z-[1950] — di atas header sticky (1200),
 * di bawah bottom sheet (2000) & search overlay (9999). Body scroll
 * dikunci via class `nat-modal-open` (konvensi repo — sekaligus
 * menyembunyikan bottom nav & WhatsApp float selama drawer terbuka).
 * Animasi slide 300ms ease-out-quart; reduced-motion → instan (CSS).
 */
export function MobileMenu() {
  const [open, setOpen] = useState(false);
  const [cats, setCats] = useState<CachedCategorySummary[]>([]);
  const closeTimer = useRef<number | null>(null);
  const pathname = usePathname();

  // Tutup drawer saat pindah halaman (tap link di dalam drawer).
  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  // Fetch kategori saat drawer pertama kali dibuka (lazy).
  useEffect(() => {
    if (!open || cats.length > 0) return;
    const cached = readCategoryCache();
    if (cached) setCats(cached.categories);
    if (!isCategoryCacheFresh(cached)) {
      fetch("/api/categories", { cache: "force-cache" })
        .then((r) => (r.ok ? r.json() : null))
        .then((p) => {
          if (Array.isArray(p?.categories)) {
            setCats(p.categories);
            writeCategoryCache(p.categories);
          }
        })
        .catch(() => {});
    }
  }, [open, cats.length]);

  // Body scroll lock + Esc close selama drawer terbuka.
  useEffect(() => {
    if (!open) return undefined;
    document.body.classList.add("nat-modal-open");
    document.body.style.overflow = "hidden";
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    window.addEventListener("keydown", onKey);
    return () => {
      document.body.classList.remove("nat-modal-open");
      document.body.style.overflow = "";
      window.removeEventListener("keydown", onKey);
    };
  }, [open]);

  useEffect(() => {
    return () => {
      if (closeTimer.current) window.clearTimeout(closeTimer.current);
    };
  }, []);

  function close() {
    // Tunda sedikit supaya tap backdrop/tutup tetap terasa smooth sebelum
    // panel hilang (transisi CSS tetap jalan karena unmount tak terjadi —
    // panel cuma translate keluar; state open dipakai untuk class).
    setOpen(false);
  }
  void closeTimer;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label="Buka menu"
        aria-expanded={open}
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-zinc-800 transition active:scale-90 active:bg-zinc-100 md:hidden"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-6 w-6" aria-hidden>
          <path d="M4 6h16M4 12h16M4 18h16" strokeLinecap="round" />
        </svg>
      </button>

      {/* Backdrop */}
      <div
        onClick={close}
        aria-hidden
        className={`fixed inset-0 z-[1900] bg-black/45 transition-opacity duration-300 ${
          open ? "opacity-100" : "pointer-events-none opacity-0"
        }`}
      />

      {/* Panel */}
      <aside
        role="dialog"
        aria-modal="true"
        aria-label="Menu navigasi"
        className={`fixed left-0 top-0 z-[1950] flex h-dvh w-[82%] max-w-[320px] flex-col bg-white shadow-2xl transition-transform duration-300 [transition-timing-function:cubic-bezier(0.25,1,0.5,1)] motion-reduce:transition-none ${
          open ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        <div className="flex items-center justify-between border-b border-zinc-100 px-4 py-3">
          <span className="text-sm font-black text-natalo-700">Menu Natalo</span>
          <button
            type="button"
            onClick={close}
            aria-label="Tutup menu"
            className="flex h-9 w-9 items-center justify-center rounded-full text-zinc-600 active:bg-zinc-100"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} className="h-5 w-5" aria-hidden>
              <path d="M6 6l12 12M18 6L6 18" strokeLinecap="round" />
            </svg>
          </button>
        </div>

        <nav className="flex-1 overflow-y-auto overscroll-contain px-4 py-4">
          <p className="text-[11px] font-black uppercase tracking-wide text-zinc-400">
            Kategori
          </p>
          <ul className="mt-2 space-y-0.5">
            {cats.slice(0, 12).map((c) => (
              <li key={c.id}>
                <Link
                  href={`/products?kategori=${encodeURIComponent(c.slug)}`}
                  className="flex items-center justify-between rounded-xl px-3 py-2.5 text-sm font-semibold text-zinc-700 transition active:bg-natalo-50 hover:bg-natalo-50 hover:text-natalo-700"
                >
                  {c.name}
                  <span aria-hidden className="text-xs text-zinc-300">
                    ›
                  </span>
                </Link>
              </li>
            ))}
            {cats.length === 0 && (
              <li className="px-3 py-2 text-sm text-zinc-400">Memuat kategori…</li>
            )}
          </ul>

          <p className="mt-5 text-[11px] font-black uppercase tracking-wide text-zinc-400">
            Jelajahi
          </p>
          <ul className="mt-2 space-y-0.5">
            {STATIC_LINKS.map((l) => (
              <li key={l.href}>
                <Link
                  href={l.href}
                  className="block rounded-xl px-3 py-2.5 text-sm font-semibold text-zinc-700 transition active:bg-natalo-50 hover:bg-natalo-50 hover:text-natalo-700"
                >
                  {l.label}
                </Link>
              </li>
            ))}
          </ul>

          <p className="mt-5 text-[11px] font-black uppercase tracking-wide text-zinc-400">
            Kunjungi Toko
          </p>
          <div className="mt-2 rounded-2xl border border-zinc-100 bg-zinc-50 p-3">
            <p className="text-xs leading-relaxed text-zinc-600">{STORE_ADDRESS}</p>
            <a
              href={MAPS_HREF}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-2 inline-flex items-center gap-1.5 text-xs font-bold text-natalo-700 active:opacity-70"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-3.5 w-3.5" aria-hidden>
                <path d="M12 21s-7-5.5-7-11a7 7 0 1 1 14 0c0 5.5-7 11-7 11Z" strokeLinecap="round" strokeLinejoin="round" />
                <circle cx="12" cy="10" r="2.5" />
              </svg>
              Buka di Google Maps
            </a>
          </div>
        </nav>
      </aside>
    </>
  );
}
