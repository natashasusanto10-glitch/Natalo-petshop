"use client";

/**
 * Compact full-width search bar untuk halaman katalog produk.
 * - No tombol Cari (sesuai spec UX).
 * - Submit by Enter (or instant kalau pakai debounce mode).
 * - Debounce 400ms untuk reduce URL spam.
 * - Sync ke URL query param ?q=<value> via router.replace (tidak push,
 *   supaya tidak isi history).
 */

import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";

const DEBOUNCE_MS = 400;

export function ProductSearchBar({
  defaultValue = "",
  showBackButton = false,
}: {
  defaultValue?: string;
  showBackButton?: boolean;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [value, setValue] = useState(defaultValue);
  const lastPushed = useRef(defaultValue);

  // Sync state ↔ URL kalau user navigate via back/forward
  useEffect(() => {
    setValue(defaultValue);
    lastPushed.current = defaultValue;
  }, [defaultValue]);

  // Debounced URL sync
  useEffect(() => {
    const trimmed = value.trim();
    if (trimmed === lastPushed.current) return;
    const timer = window.setTimeout(() => {
      const params = new URLSearchParams(searchParams.toString());
      if (trimmed) params.set("q", trimmed);
      else params.delete("q");
      params.delete("page");
      lastPushed.current = trimmed;
      router.replace(`/products${params.toString() ? `?${params}` : ""}`, {
        scroll: false,
      });
    }, DEBOUNCE_MS);
    return () => window.clearTimeout(timer);
  }, [value, router, searchParams]);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    // Flush — push langsung tanpa debounce
    const trimmed = value.trim();
    const params = new URLSearchParams(searchParams.toString());
    if (trimmed) params.set("q", trimmed);
    else params.delete("q");
    params.delete("page");
    lastPushed.current = trimmed;
    router.push(`/products${params.toString() ? `?${params}` : ""}`, {
      scroll: false,
    });
  }

  function handleClear() {
    setValue("");
    const params = new URLSearchParams(searchParams.toString());
    params.delete("q");
    params.delete("page");
    lastPushed.current = "";
    router.replace(`/products${params.toString() ? `?${params}` : ""}`, {
      scroll: false,
    });
  }

  function handleBack() {
    if (typeof window !== "undefined" && window.history.length > 1) {
      router.back();
    } else {
      router.push("/products");
    }
  }

  return (
    <div className={showBackButton ? "flex w-full items-center gap-2" : "w-full"}>
      {showBackButton && (
        <button
          type="button"
          onClick={handleBack}
          aria-label="Kembali"
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-slate-800 transition active:bg-slate-100"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={2.2}
            className="h-5 w-5"
            aria-hidden
          >
            <path d="M15 18l-6-6 6-6" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
      )}
      <form onSubmit={handleSubmit} className="min-w-0 flex-1">
      <div className="flex h-12 w-full items-center rounded-2xl border border-slate-200 bg-white px-4 shadow-sm">
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={2}
          className="mr-3 h-5 w-5 shrink-0 text-slate-400"
          aria-hidden
        >
          <circle cx="11" cy="11" r="8" />
          <line x1="21" y1="21" x2="16.65" y2="16.65" />
        </svg>
        <input
          value={value}
          onChange={(e) => setValue(e.target.value)}
          type="search"
          inputMode="search"
          enterKeyHint="search"
          placeholder="Cari produk di Natalo..."
          className="h-full w-full bg-transparent text-sm font-medium text-slate-900 outline-none placeholder:text-slate-400"
        />
        {value && (
          <button
            type="button"
            aria-label="Hapus pencarian"
            onClick={handleClear}
            className="ml-2 flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-slate-400 transition active:bg-slate-100 active:text-slate-600"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth={2.4}
              className="h-4 w-4"
            >
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        )}
      </div>
      </form>
    </div>
  );
}
