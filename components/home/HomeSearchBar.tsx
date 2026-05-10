"use client";

import { useState } from "react";
import { SearchOverlay } from "@/components/SearchOverlay";

// `waUrl` masih diterima supaya call-site di app/page.tsx tidak perlu diubah,
// tapi tombol customer-service WhatsApp di samping search bar sudah dihapus
// sesuai design (FAB WhatsApp tetap aktif via components/WhatsAppFloat).
export function HomeSearchBar({ waUrl: _waUrl }: { waUrl?: string }) {
  void _waUrl;
  const [open, setOpen] = useState(false);

  return (
    <>
      <div className="nat-safe-x sticky z-40 bg-[#FAFAFA] pb-3 pt-3 shadow-[0_1px_0_rgba(0,0,0,0.04)] [top:env(safe-area-inset-top)] md:hidden">
        <button
          type="button"
          onClick={() => setOpen(true)}
          aria-label="Buka pencarian"
          className="flex w-full items-center gap-2 rounded-full border border-[#f0f0f0] bg-white px-4 py-2.5 text-left shadow-sm transition hover:border-blue-200"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={1.8}
            strokeLinecap="round"
            strokeLinejoin="round"
            className="h-4 w-4 shrink-0 text-zinc-400"
            aria-hidden
          >
            <circle cx="11" cy="11" r="7" />
            <path d="m20 20-3.5-3.5" />
          </svg>
          <span className="flex-1 truncate text-sm text-zinc-400">
            Cari di Natalo Petshop...
          </span>
        </button>
      </div>

      <SearchOverlay open={open} onClose={() => setOpen(false)} />
    </>
  );
}
