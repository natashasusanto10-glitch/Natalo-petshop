"use client";

import { useEffect, useRef, useState } from "react";

function ChevronDownIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M6 9l6 6 6-6" />
    </svg>
  );
}

function SearchIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <circle cx="11" cy="11" r="7" />
      <path d="M21 21l-4.35-4.35" />
    </svg>
  );
}

type CategoryOption = { id: string; name: string };

export function CategoryCombobox({
  value,
  onChange,
  categories,
}: {
  value: string;
  onChange: (id: string) => void;
  categories: CategoryOption[];
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const wrapperRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function handleClickOutside(e: MouseEvent) {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [open]);

  const selectedName = value ? categories.find(c => c.id === value)?.name ?? "Kategori tidak ditemukan" : "Tanpa kategori";
  const filtered = categories.filter(c => c.name.toLowerCase().includes(query.trim().toLowerCase()));

  function selectCategory(id: string) {
    onChange(id);
    setOpen(false);
    setQuery("");
  }

  return (
    <div ref={wrapperRef} className="relative">
      <button
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => setOpen(o => !o)}
        className="flex w-full items-center justify-between rounded-xl border border-zinc-300 px-4 py-3 text-left text-sm"
      >
        <span className={value ? "text-zinc-900" : "text-zinc-500"}>{selectedName}</span>
        <ChevronDownIcon />
      </button>

      {open && (
        <div className="absolute z-20 mt-1 w-full overflow-hidden rounded-xl border border-zinc-200 bg-white shadow-lg">
          <div className="flex items-center gap-2 border-b border-zinc-200 px-3 py-2 text-zinc-500">
            <SearchIcon />
            <input
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder="Cari kategori"
              aria-label="Cari kategori"
              className="min-w-0 flex-1 text-sm text-zinc-900 outline-none"
              autoFocus
            />
          </div>
          <div className="max-h-60 overflow-y-auto py-1" role="listbox">
            <button
              type="button"
              role="option"
              aria-selected={value === ""}
              onClick={() => selectCategory("")}
              className={`block w-full px-3 py-2 text-left text-sm ${value === "" ? "bg-natalo-50 font-semibold text-zinc-900" : "text-zinc-700"}`}
            >
              Tanpa kategori
            </button>
            {filtered.map(category => (
              <button
                key={category.id}
                type="button"
                role="option"
                aria-selected={value === category.id}
                onClick={() => selectCategory(category.id)}
                className={`block w-full px-3 py-2 text-left text-sm ${value === category.id ? "bg-natalo-50 font-semibold text-zinc-900" : "text-zinc-700"}`}
              >
                {category.name}
              </button>
            ))}
            {filtered.length === 0 && <p className="px-3 py-3 text-sm text-zinc-500">Kategori tidak ditemukan</p>}
          </div>
        </div>
      )}
    </div>
  );
}
