"use client";

import { useState } from "react";
import dynamic from "next/dynamic";

// Lazy load SearchOverlay — modal full-screen yang baru di-render saat user
// tap search bar. Tanpa dynamic, search logic (debounce, MeiliSearch client
// API call, dll) masuk bundle awal home page yang gak perlu.
const SearchOverlay = dynamic(
  () => import("@/components/SearchOverlay").then((m) => m.SearchOverlay),
  { ssr: false },
);

// `waUrl` masih diterima supaya pemanggil lama tetap aman. Tombol customer-service
// WhatsApp di samping search bar sudah dihapus.
export function HomeSearchBar({
  waUrl: _waUrl,
  className = "mobile-search-wrapper md:hidden",
}: {
  waUrl?: string;
  className?: string;
}) {
  void _waUrl;
  const [open, setOpen] = useState(false);

  return (
    <>
      <div className={className}>
        <button
          type="button"
          onClick={() => setOpen(true)}
          aria-label="Buka pencarian"
          className="flex h-10 w-full items-center gap-2 rounded-full border border-natalo-200 bg-natalo-50/60 px-3 text-left shadow-sm transition active:bg-natalo-100/60"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={2}
            strokeLinecap="round"
            strokeLinejoin="round"
            className="h-4 w-4 shrink-0 text-natalo-500"
            aria-hidden
          >
            <circle cx="11" cy="11" r="7" />
            <path d="m20 20-3.5-3.5" />
          </svg>
          <span className="flex-1 truncate text-sm font-semibold text-gray-400">
            Cari produk, brand, atau kategori...
          </span>
        </button>
      </div>

      <SearchOverlay open={open} onClose={() => setOpen(false)} />
    </>
  );
}
