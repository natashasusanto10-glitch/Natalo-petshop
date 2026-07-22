"use client";

import { useEffect, useRef, useState } from "react";
import { Button, FormField } from "@/components/admin/ui";

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

function PlusIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M12 5v14M5 12h14" />
    </svg>
  );
}

type BrandOption = { id: string; name: string };

/**
 * BrandCombobox — pengganti native <select> untuk field Brand di
 * ProductForm. Searchable dropdown + aksi "Tambah brand baru" inline
 * (modal kecil, POST ke /api/admin/brands) tanpa keluar dari form produk.
 */
export function BrandCombobox({
  value,
  onChange,
  brands,
  onBrandCreated,
}: {
  value: string;
  onChange: (id: string) => void;
  brands: BrandOption[];
  onBrandCreated: (brand: BrandOption) => void;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const wrapperRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function handleClickOutside(e: MouseEvent) {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [open]);

  const selectedName = value ? brands.find(b => b.id === value)?.name ?? "Tanpa brand" : "Tanpa brand";
  const filtered = brands.filter(b => b.name.toLowerCase().includes(query.trim().toLowerCase()));

  function selectBrand(id: string) {
    onChange(id);
    setOpen(false);
  }

  async function saveNewBrand() {
    if (!name.trim()) return;
    setSaving(true);
    setError(null);
    try {
      const res = await fetch("/api/admin/brands", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: name.trim() }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(data?.error ?? "Gagal menyimpan brand.");
        setSaving(false);
        return;
      }
      onBrandCreated({ id: data.id, name: data.name });
      onChange(data.id);
      setName("");
      setModalOpen(false);
      setOpen(false);
      setSaving(false);
    } catch {
      setError("Gagal menyimpan brand.");
      setSaving(false);
    }
  }

  function closeModal() {
    setModalOpen(false);
    setName("");
    setError(null);
  }

  return (
    <div ref={wrapperRef} className="relative">
      <button
        type="button"
        onClick={() => setOpen(o => !o)}
        className="flex w-full items-center justify-between rounded-xl border border-zinc-300 px-4 py-3 text-sm"
      >
        <span className={value ? "text-zinc-900" : "text-zinc-500"}>{selectedName}</span>
        <ChevronDownIcon />
      </button>

      {open && (
        <div className="absolute z-10 mt-1 w-full rounded-xl border border-zinc-200 bg-white shadow-lg">
          <div className="flex items-center gap-2 border-b border-zinc-200 px-3 py-2 text-zinc-500">
            <SearchIcon />
            <input
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder="Cari brand"
              className="flex-1 text-sm text-zinc-900 outline-none"
              autoFocus
            />
          </div>
          <button
            type="button"
            onClick={() => setModalOpen(true)}
            className="flex w-full items-center gap-2 bg-natalo-50 px-3 py-2 text-sm font-bold text-natalo-700"
          >
            <PlusIcon />
            Tambah brand baru
          </button>
          <div className="max-h-60 overflow-y-auto py-1">
            <button
              type="button"
              onClick={() => selectBrand("")}
              className={`block w-full px-3 py-2 text-left text-sm ${value === "" ? "bg-natalo-50 font-semibold text-zinc-900" : "text-zinc-700"}`}
            >
              Tanpa brand
            </button>
            {filtered.map(b => (
              <button
                key={b.id}
                type="button"
                onClick={() => selectBrand(b.id)}
                className={`block w-full px-3 py-2 text-left text-sm ${value === b.id ? "bg-natalo-50 font-semibold text-zinc-900" : "text-zinc-700"}`}
              >
                {b.name}
              </button>
            ))}
          </div>
        </div>
      )}

      {modalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
          <div className="w-full max-w-sm rounded-2xl border border-zinc-200 bg-white p-5 shadow-xl">
            <h2 className="text-base font-bold text-zinc-950">Tambah brand baru</h2>
            <p className="mt-1 text-xs text-zinc-500">Brand langsung terpilih di form setelah disimpan.</p>
            <div className="mt-4">
              <FormField label="Nama brand" error={error ?? undefined}>
                <input
                  value={name}
                  onChange={e => setName(e.target.value)}
                  autoFocus
                  className="block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm"
                />
              </FormField>
            </div>
            <div className="mt-5 flex justify-end gap-2">
              <Button type="button" variant="secondary" onClick={closeModal}>Batal</Button>
              <Button type="button" disabled={saving} onClick={() => void saveNewBrand()}>
                {saving ? "Menyimpan..." : "Simpan"}
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
