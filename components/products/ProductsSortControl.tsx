"use client";

import { useState } from "react";
import { BottomSheet } from "@/components/BottomSheet";
import type { SearchSort } from "@/lib/search";

/** Label disamakan dengan app Flutter supaya web & app satu bahasa. */
export const PRODUCTS_SORT_OPTIONS: { value: SearchSort; label: string }[] = [
  { value: "relevance", label: "Paling Sesuai" },
  { value: "best_seller", label: "Paling Populer" },
  { value: "trending", label: "Trending" },
  { value: "newest", label: "Terbaru" },
  { value: "rating_desc", label: "Rating Tertinggi" },
  { value: "price_asc", label: "Harga Terendah" },
  { value: "price_desc", label: "Harga Tertinggi" },
];

export function ProductsSortControl({
  sort,
  onSortChange,
}: {
  sort: SearchSort;
  onSortChange: (next: SearchSort) => void;
}) {
  const [open, setOpen] = useState(false);
  const active = PRODUCTS_SORT_OPTIONS.find((o) => o.value === sort) ?? PRODUCTS_SORT_OPTIONS[0];

  return (
    <>
      {/* Desktop: select native — 6 opsi terlalu lebar untuk segmented. */}
      <label className="hidden items-center gap-2 md:inline-flex">
        <span className="text-xs font-semibold text-zinc-500">Urutkan</span>
        <select
          value={sort}
          onChange={(event) => onSortChange(event.target.value as SearchSort)}
          className="h-9 rounded-full border border-gray-200 bg-white px-3 text-xs font-extrabold text-gray-800 outline-none focus:border-natalo-500 focus:ring-2 focus:ring-natalo-100"
        >
          {PRODUCTS_SORT_OPTIONS.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      </label>

      {/* Mobile: bottom-sheet ala app. */}
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-haspopup="dialog"
        aria-expanded={open}
        className="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full border border-gray-200 bg-white px-3 text-xs font-extrabold text-gray-800 active:bg-gray-50 md:hidden"
      >
        Urut: {active.label}
      </button>

      <BottomSheet open={open} onClose={() => setOpen(false)} title="Urutkan berdasarkan">
        <div className="-mx-1 space-y-1">
          {PRODUCTS_SORT_OPTIONS.map((option) => {
            const selected = option.value === sort;
            return (
              <button
                key={option.value}
                type="button"
                onClick={() => {
                  onSortChange(option.value);
                  setOpen(false);
                }}
                className={`flex h-12 w-full items-center justify-between rounded-2xl px-4 text-left text-sm font-extrabold transition active:bg-natalo-50 ${
                  selected ? "bg-natalo-50 text-natalo-700" : "text-gray-800"
                }`}
              >
                <span>{option.label}</span>
                {selected && <span className="text-natalo-600">✓</span>}
              </button>
            );
          })}
        </div>
      </BottomSheet>
    </>
  );
}
