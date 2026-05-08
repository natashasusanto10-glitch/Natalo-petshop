"use client";

import { useState } from "react";
import { SearchOverlay } from "@/components/SearchOverlay";

export function HomeSearchBar({ waUrl }: { waUrl: string }) {
  const [open, setOpen] = useState(false);

  return (
    <>
      <div className="sticky top-[76px] z-30 bg-[#FAFAFA]/95 px-4 py-3 backdrop-blur-md md:hidden">
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => setOpen(true)}
            aria-label="Buka pencarian"
            className="flex flex-1 items-center gap-2 rounded-full border border-[#f0f0f0] bg-white px-4 py-2.5 text-left shadow-sm transition hover:border-orange-200"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth={2}
              className="h-4 w-4 shrink-0 text-zinc-400"
              aria-hidden
            >
              <circle cx="11" cy="11" r="8" />
              <path d="M21 21l-4.35-4.35" />
            </svg>
            <span className="flex-1 truncate text-sm text-zinc-400">
              Cari di Natalo Petshop...
            </span>
            <span
              aria-hidden
              className="flex h-6 w-6 items-center justify-center rounded-full text-orange-500"
            >
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.8"
                strokeLinecap="round"
                strokeLinejoin="round"
                className="h-4 w-4"
              >
                <rect x="9" y="3" width="6" height="11" rx="3" />
                <path d="M5 11a7 7 0 0 0 14 0M12 18v3" />
              </svg>
            </span>
          </button>

          <a
            href={waUrl}
            target="_blank"
            rel="noreferrer"
            aria-label="Hubungi customer service"
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-orange-500 text-white shadow-sm active:opacity-90"
          >
            <svg viewBox="0 0 24 24" fill="currentColor" className="h-5 w-5">
              <path d="M20.52 3.48A12 12 0 0 0 3.5 20.36L2 22l1.69-1.55A12 12 0 1 0 20.52 3.48Zm-8.4 18a10 10 0 0 1-5.1-1.4l-.36-.21-3.06.86.82-3-.24-.38a10 10 0 1 1 7.94 4.13Zm5.5-7.5c-.3-.15-1.78-.88-2-1s-.5-.15-.7.15-.82 1-1 1.2-.36.22-.66.07a8.2 8.2 0 0 1-2.4-1.48 9.05 9.05 0 0 1-1.66-2.07c-.17-.3 0-.46.13-.61s.3-.36.45-.54a2.1 2.1 0 0 0 .3-.5.55.55 0 0 0 0-.53c-.07-.15-.7-1.67-.95-2.28s-.5-.52-.7-.53h-.6a1.16 1.16 0 0 0-.83.39 3.5 3.5 0 0 0-1.1 2.6 6.07 6.07 0 0 0 1.27 3.23 13.92 13.92 0 0 0 5.34 4.7c.74.32 1.32.5 1.78.65a4.3 4.3 0 0 0 2 .12 3.24 3.24 0 0 0 2.13-1.5 2.65 2.65 0 0 0 .19-1.5c-.07-.13-.27-.2-.57-.35Z" />
            </svg>
          </a>
        </div>
      </div>

      <SearchOverlay open={open} onClose={() => setOpen(false)} />
    </>
  );
}
