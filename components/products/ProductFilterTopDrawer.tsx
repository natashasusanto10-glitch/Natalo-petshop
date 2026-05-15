"use client";

/**
 * Top drawer filter ala Netflix — slide down dari atas ke bawah.
 *
 * 4 section utama:
 * 1. Semua — reset semua filter, tutup drawer
 * 2. Kategori (accordion) — list dari DB categories
 * 3. Produk Baru (accordion) — today/this-week/this-month/newest
 * 4. Populer (accordion) — best-seller/most-searched/highest-rating/most-bought
 *
 * Klik item pilihan: set filter via URL params + tutup drawer + scroll up.
 * Klik overlay (di luar drawer): tutup tanpa apply filter.
 *
 * Body class `top-drawer-open` di-set saat open, supaya WhatsAppFloat &
 * SwipeBackProvider bisa detect via CSS / body-class check.
 */

import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState, useTransition } from "react";
import { createPortal } from "react-dom";
import { hapticTap } from "@/lib/native/haptics";

export type FilterSection = "kategori" | "produk-baru" | "populer";

export type CategoryOption = { slug: string; name: string };

type Props = {
  open: boolean;
  onClose: () => void;
  /** Section yg auto-expanded saat drawer open */
  defaultSection?: FilterSection | null;
  /** Kategori list dari DB (slug + name) */
  categories: CategoryOption[];
  /** Filter aktif saat ini (dari URL params) */
  activeCategory: string | null;
  activeNewFilter: string | null;
  activePopularFilter: string | null;
};

const NEW_OPTIONS = [
  { id: "today", label: "Hari Ini" },
  { id: "this-week", label: "Minggu Ini" },
  { id: "this-month", label: "Bulan Ini" },
  { id: "newest", label: "Produk Terbaru" },
];

const POPULAR_OPTIONS = [
  { id: "best-seller", label: "Terlaris" },
  { id: "most-searched", label: "Paling Dicari" },
  { id: "highest-rating", label: "Rating Tertinggi" },
  { id: "most-bought", label: "Paling Banyak Dibeli" },
];

function ChevronDown({ className = "h-4 w-4" }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className={className} aria-hidden>
      <path d="M6 9l6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5} className="h-4 w-4 shrink-0" aria-hidden>
      <path d="M5 12l5 5L20 7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function ProductFilterTopDrawer({
  open,
  onClose,
  defaultSection,
  categories,
  activeCategory,
  activeNewFilter,
  activePopularFilter,
}: Props) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [expanded, setExpanded] = useState<FilterSection | null>(defaultSection ?? null);
  const [, startTransition] = useTransition();

  // Sync expanded section dgn trigger source
  useEffect(() => {
    if (open) setExpanded(defaultSection ?? null);
  }, [open, defaultSection]);

  // Lock body scroll + body class + ESC close
  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    document.body.classList.add("top-drawer-open");
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      document.body.classList.remove("top-drawer-open");
      document.removeEventListener("keydown", onKey);
    };
  }, [open, onClose]);

  function applyAndClose(updater: (params: URLSearchParams) => void) {
    const params = new URLSearchParams(searchParams.toString());
    updater(params);
    params.delete("page");
    hapticTap();
    onClose();
    startTransition(() => {
      router.push(`/products${params.toString() ? `?${params}` : ""}`, {
        scroll: false,
      });
    });
  }

  function handleResetAll() {
    applyAndClose((params) => {
      params.delete("kategori");
      params.delete("category");
      params.delete("new");
      params.delete("popular");
    });
  }

  function handleSelectCategory(slug: string) {
    applyAndClose((params) => {
      if (params.get("kategori") === slug) {
        params.delete("kategori");
      } else {
        params.set("kategori", slug);
      }
    });
  }

  function handleSelectNew(id: string) {
    applyAndClose((params) => {
      if (params.get("new") === id) {
        params.delete("new");
      } else {
        params.set("new", id);
        params.delete("popular");
      }
    });
  }

  function handleSelectPopular(id: string) {
    applyAndClose((params) => {
      if (params.get("popular") === id) {
        params.delete("popular");
      } else {
        params.set("popular", id);
        params.delete("new");
      }
    });
  }

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <div className="fixed inset-0 z-[9999]" role="dialog" aria-modal="true" aria-label="Filter produk">
      <button
        type="button"
        aria-label="Tutup filter"
        onClick={onClose}
        className="absolute inset-0 bg-black/30 backdrop-blur-sm animate-in fade-in duration-200"
      />

      <div
        className="relative mt-[calc(env(safe-area-inset-top)_+_0.75rem)] overflow-hidden rounded-[28px] bg-white shadow-2xl animate-in slide-in-from-top-4 fade-in duration-200"
        style={{
          maxHeight: "min(88dvh, calc(100dvh - env(safe-area-inset-top) - 1.5rem))",
        }}
      >
        {/* Drag handle */}
        <div className="flex justify-center pt-3">
          <div className="h-1.5 w-14 rounded-full bg-slate-300" />
        </div>

        <div
          className="overflow-y-auto px-5 pb-6 pt-3"
          style={{
            maxHeight: "calc(min(88dvh, calc(100dvh - env(safe-area-inset-top) - 1.5rem)) - 2.75rem)",
          }}
        >
          {/* Semua — instant reset */}
          <button
            type="button"
            onClick={handleResetAll}
            className={`flex w-full items-center justify-between gap-3 rounded-2xl border px-4 py-3 text-left transition ${
              !activeCategory && !activeNewFilter && !activePopularFilter
                ? "border-blue-200 bg-blue-50 text-blue-700"
                : "border-slate-100 bg-white text-slate-900 active:bg-slate-50"
            }`}
          >
            <span className="flex items-center gap-3">
              <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-blue-100 text-blue-600">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5" aria-hidden>
                  <rect x="3" y="3" width="7" height="7" rx="1.5" />
                  <rect x="14" y="3" width="7" height="7" rx="1.5" />
                  <rect x="3" y="14" width="7" height="7" rx="1.5" />
                  <rect x="14" y="14" width="7" height="7" rx="1.5" />
                </svg>
              </span>
              <span className="min-w-0">
                <span className="block text-sm font-bold">Semua</span>
                <span className="mt-0.5 block text-xs text-slate-500">Tampilkan semua produk</span>
              </span>
            </span>
            {!activeCategory && !activeNewFilter && !activePopularFilter && <CheckIcon />}
          </button>

          {/* Kategori accordion */}
          <Accordion
            label="Kategori"
            open={expanded === "kategori"}
            badge={activeCategory ? categories.find((c) => c.slug === activeCategory)?.name : undefined}
            onToggle={() => setExpanded(expanded === "kategori" ? null : "kategori")}
          >
            <ul className="space-y-1.5 pt-2">
              {categories.map((c) => {
                const isActive = activeCategory === c.slug;
                return (
                  <li key={c.slug}>
                    <button
                      type="button"
                      onClick={() => handleSelectCategory(c.slug)}
                      className={`flex w-full items-center justify-between rounded-xl px-3 py-2.5 text-left text-sm font-semibold transition ${
                        isActive
                          ? "bg-blue-50 text-blue-700"
                          : "bg-white text-slate-700 active:bg-slate-50"
                      }`}
                    >
                      <span>{c.name}</span>
                      {isActive && <CheckIcon />}
                    </button>
                  </li>
                );
              })}
              {categories.length === 0 && (
                <p className="px-3 py-2 text-xs text-slate-500">Belum ada kategori.</p>
              )}
            </ul>
          </Accordion>

          {/* Produk Baru accordion */}
          <Accordion
            label="Produk Baru"
            open={expanded === "produk-baru"}
            badge={NEW_OPTIONS.find((o) => o.id === activeNewFilter)?.label}
            onToggle={() => setExpanded(expanded === "produk-baru" ? null : "produk-baru")}
          >
            <ul className="space-y-1.5 pt-2">
              {NEW_OPTIONS.map((o) => {
                const isActive = activeNewFilter === o.id;
                return (
                  <li key={o.id}>
                    <button
                      type="button"
                      onClick={() => handleSelectNew(o.id)}
                      className={`flex w-full items-center justify-between rounded-xl px-3 py-2.5 text-left text-sm font-semibold transition ${
                        isActive
                          ? "bg-blue-50 text-blue-700"
                          : "bg-white text-slate-700 active:bg-slate-50"
                      }`}
                    >
                      <span>{o.label}</span>
                      {isActive && <CheckIcon />}
                    </button>
                  </li>
                );
              })}
            </ul>
          </Accordion>

          {/* Populer accordion */}
          <Accordion
            label="Populer"
            open={expanded === "populer"}
            badge={POPULAR_OPTIONS.find((o) => o.id === activePopularFilter)?.label}
            onToggle={() => setExpanded(expanded === "populer" ? null : "populer")}
            last
          >
            <ul className="space-y-1.5 pt-2">
              {POPULAR_OPTIONS.map((o) => {
                const isActive = activePopularFilter === o.id;
                return (
                  <li key={o.id}>
                    <button
                      type="button"
                      onClick={() => handleSelectPopular(o.id)}
                      className={`flex w-full items-center justify-between rounded-xl px-3 py-2.5 text-left text-sm font-semibold transition ${
                        isActive
                          ? "bg-blue-50 text-blue-700"
                          : "bg-white text-slate-700 active:bg-slate-50"
                      }`}
                    >
                      <span>{o.label}</span>
                      {isActive && <CheckIcon />}
                    </button>
                  </li>
                );
              })}
            </ul>
          </Accordion>
        </div>
      </div>
    </div>,
    document.body,
  );
}

function Accordion({
  label,
  badge,
  open,
  onToggle,
  children,
  last = false,
}: {
  label: string;
  badge?: string;
  open: boolean;
  onToggle: () => void;
  children: React.ReactNode;
  last?: boolean;
}) {
  return (
    <div className={`border-t border-slate-100 pt-3 ${last ? "" : "pb-1"} mt-3`}>
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center justify-between gap-3 text-left"
      >
        <span className="flex items-baseline gap-2">
          <span className="text-sm font-bold text-slate-900">{label}</span>
          {badge && (
            <span className="rounded-full bg-blue-100 px-2 py-0.5 text-[11px] font-bold text-blue-700">
              {badge}
            </span>
          )}
        </span>
        <ChevronDown
          className={`h-4 w-4 text-slate-500 transition-transform ${open ? "rotate-180" : ""}`}
        />
      </button>
      {open && <div className="mt-1">{children}</div>}
    </div>
  );
}
