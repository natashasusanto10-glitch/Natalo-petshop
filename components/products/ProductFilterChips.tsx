"use client";

/**
 * Row of filter chips di bawah search bar.
 * 4 chips: Semua (fixed reset), Kategori ˅, Produk Baru ˅, Populer ˅.
 *
 * Chip yg punya filter aktif tampil dengan badge value (mis. "Kategori:
 * Aquarium & Ikan") + tombol × untuk clear filter spesifik tsb.
 *
 * Klik chip tanpa filter aktif → buka drawer di section yg sesuai.
 * Klik "Semua" → instant reset semua filter (tidak buka drawer).
 *
 * Horizontal scroll di mobile kalau chip overflow.
 */

import { useRouter, useSearchParams } from "next/navigation";
import { useState, useTransition } from "react";
import {
  ProductFilterTopDrawer,
  type CategoryOption,
  type FilterSection,
} from "./ProductFilterTopDrawer";
import { hapticTap } from "@/lib/native/haptics";

const NEW_LABELS: Record<string, string> = {
  today: "Hari Ini",
  "this-week": "Minggu Ini",
  "this-month": "Bulan Ini",
  newest: "Produk Terbaru",
};

const POPULAR_LABELS: Record<string, string> = {
  "best-seller": "Terlaris",
  "most-searched": "Paling Dicari",
  "highest-rating": "Rating Tertinggi",
  "most-bought": "Paling Banyak Dibeli",
};

type Props = {
  categories: CategoryOption[];
  activeCategory: string | null;
  activeNewFilter: string | null;
  activePopularFilter: string | null;
};

function ChevronDown() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-3.5 w-3.5" aria-hidden>
      <path d="M6 9l6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function CloseX() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} className="h-3 w-3" aria-hidden>
      <line x1="18" y1="6" x2="6" y2="18" />
      <line x1="6" y1="6" x2="18" y2="18" />
    </svg>
  );
}

export function ProductFilterChips({
  categories,
  activeCategory,
  activeNewFilter,
  activePopularFilter,
}: Props) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [defaultSection, setDefaultSection] = useState<FilterSection | null>(null);
  // useTransition supaya navigasi filter (router.push) jadi non-urgent —
  // isPending = true selama server re-render produk grid. Kita pakai itu
  // untuk dim chip row & disable interaksi biar user dapat feedback visual
  // instan, bukan UI freeze.
  const [isPending, startTransition] = useTransition();

  const hasNoFilter = !activeCategory && !activeNewFilter && !activePopularFilter;

  function openDrawerAt(section: FilterSection) {
    hapticTap();
    setDefaultSection(section);
    setDrawerOpen(true);
  }

  function clearOne(key: "kategori" | "new" | "popular") {
    hapticTap();
    const params = new URLSearchParams(searchParams.toString());
    params.delete(key);
    params.delete("page");
    startTransition(() => {
      router.push(`/products${params.toString() ? `?${params}` : ""}`, {
        scroll: false,
      });
    });
  }

  function resetAll() {
    hapticTap();
    const params = new URLSearchParams(searchParams.toString());
    params.delete("kategori");
    params.delete("category");
    params.delete("new");
    params.delete("popular");
    params.delete("page");
    startTransition(() => {
      router.push(`/products${params.toString() ? `?${params}` : ""}`, {
        scroll: false,
      });
    });
  }

  const categoryName = activeCategory
    ? categories.find((c) => c.slug === activeCategory)?.name ?? activeCategory
    : null;
  const newLabel = activeNewFilter ? NEW_LABELS[activeNewFilter] ?? activeNewFilter : null;
  const popularLabel = activePopularFilter
    ? POPULAR_LABELS[activePopularFilter] ?? activePopularFilter
    : null;

  return (
    <>
      <div
        aria-busy={isPending}
        className={`-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 transition-opacity duration-150 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden ${
          isPending ? "pointer-events-none opacity-60" : ""
        }`}
      >
        {/* Semua */}
        <button
          type="button"
          onClick={resetAll}
          className={`shrink-0 rounded-full border px-4 py-1.5 text-sm font-semibold transition ${
            hasNoFilter
              ? "border-blue-500 bg-blue-500 text-white"
              : "border-slate-200 bg-white text-slate-700 active:bg-slate-50"
          }`}
        >
          Semua
        </button>

        {/* Kategori */}
        <ChipWithDropdown
          active={!!categoryName}
          label={categoryName ? `Kategori: ${categoryName}` : "Kategori"}
          onOpen={() => openDrawerAt("kategori")}
          onClear={categoryName ? () => clearOne("kategori") : undefined}
        />

        {/* Produk Baru */}
        <ChipWithDropdown
          active={!!newLabel}
          label={newLabel ? `Produk Baru: ${newLabel}` : "Produk Baru"}
          onOpen={() => openDrawerAt("produk-baru")}
          onClear={newLabel ? () => clearOne("new") : undefined}
        />

        {/* Populer */}
        <ChipWithDropdown
          active={!!popularLabel}
          label={popularLabel ? `Populer: ${popularLabel}` : "Populer"}
          onOpen={() => openDrawerAt("populer")}
          onClear={popularLabel ? () => clearOne("popular") : undefined}
        />
      </div>

      <ProductFilterTopDrawer
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        defaultSection={defaultSection}
        categories={categories}
        activeCategory={activeCategory}
        activeNewFilter={activeNewFilter}
        activePopularFilter={activePopularFilter}
      />
    </>
  );
}

function ChipWithDropdown({
  active,
  label,
  onOpen,
  onClear,
}: {
  active: boolean;
  label: string;
  onOpen: () => void;
  onClear?: () => void;
}) {
  return (
    <span
      className={`flex shrink-0 items-center gap-1.5 rounded-full border pl-3 pr-3 py-1.5 text-sm font-semibold transition ${
        active
          ? "border-blue-500 bg-blue-500 text-white"
          : "border-slate-200 bg-white text-slate-700"
      }`}
    >
      <button
        type="button"
        onClick={onOpen}
        className="flex items-center gap-1.5"
      >
        <span className="whitespace-nowrap">{label}</span>
        {!onClear && <ChevronDown />}
      </button>
      {onClear && (
        <button
          type="button"
          aria-label="Hapus filter ini"
          onClick={onClear}
          className="-mr-1 ml-0.5 flex h-5 w-5 items-center justify-center rounded-full bg-white/20 text-current active:bg-white/30"
        >
          <CloseX />
        </button>
      )}
    </span>
  );
}
