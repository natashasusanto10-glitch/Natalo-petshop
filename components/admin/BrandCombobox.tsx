"use client";

import { useEffect, useRef, useState } from "react";
import { AdminDialog } from "./ui/AdminDialog";
import { Button, FormField } from "@/components/admin/ui";

function ChevronDownIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M6 9l6 6 6-6" />
    </svg>
  );
}

function SearchIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <circle cx="11" cy="11" r="7" />
      <path d="M21 21l-4.35-4.35" />
    </svg>
  );
}

function PlusIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
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
      if (
        wrapperRef.current &&
        !wrapperRef.current.contains(e.target as Node)
      ) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [open]);

  const selectedName = value
    ? brands.find((b) => b.id === value)?.name ?? "Tanpa brand"
    : "Tanpa brand";
  const filtered = brands.filter((b) =>
    b.name.toLowerCase().includes(query.trim().toLowerCase())
  );

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
    <div
      ref={wrapperRef}
      className="relative"
      onKeyDown={(event) => {
        if (event.key === "Escape" && open) {
          event.preventDefault();
          setOpen(false);
          wrapperRef.current
            ?.querySelector<HTMLButtonElement>("button")
            ?.focus();
        }
      }}
    >
      <button
        type="button"
        aria-label={`Brand: ${selectedName}`}
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className="admin-field-control flex items-center justify-between text-left"
      >
        <span className={value ? "text-zinc-900" : "text-zinc-500"}>
          {selectedName}
        </span>
        <ChevronDownIcon />
      </button>

      {open && (
        <div className="admin-combobox-panel absolute z-20 mt-1 w-full rounded-xl border border-zinc-200 bg-white shadow-lg">
          <div className="flex items-center gap-2 border-b border-zinc-200 px-3 py-2 text-zinc-500">
            <SearchIcon />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              aria-label="Cari brand"
              placeholder="Cari brand"
              className="min-w-0 flex-1 text-sm text-zinc-900 outline-none"
              autoFocus
            />
          </div>
          <button
            type="button"
            onClick={() => {
              setOpen(false);
              wrapperRef.current
                ?.querySelector<HTMLButtonElement>("button")
                ?.focus();
              setModalOpen(true);
            }}
            className="flex min-h-11 w-full items-center gap-2 bg-natalo-50 px-3 py-2 text-sm font-bold text-natalo-700"
          >
            <PlusIcon />
            Tambah brand baru
          </button>
          <div
            className="max-h-60 overflow-y-auto py-1"
            role="listbox"
            aria-label="Brand"
          >
            <button
              type="button"
              role="option"
              aria-selected={value === ""}
              onClick={() => selectBrand("")}
              className={`block min-h-11 w-full px-3 py-2 text-left text-sm ${
                value === ""
                  ? "bg-natalo-50 font-semibold text-zinc-900"
                  : "text-zinc-700"
              }`}
            >
              Tanpa brand
            </button>
            {filtered.map((b) => (
              <button
                key={b.id}
                type="button"
                role="option"
                aria-selected={value === b.id}
                onClick={() => selectBrand(b.id)}
                className={`block min-h-11 w-full px-3 py-2 text-left text-sm ${
                  value === b.id
                    ? "bg-natalo-50 font-semibold text-zinc-900"
                    : "text-zinc-700"
                }`}
              >
                {b.name}
              </button>
            ))}
          </div>
        </div>
      )}

      <AdminDialog
        open={modalOpen}
        title="Tambah brand baru"
        busy={saving}
        onClose={closeModal}
        footer={
          <>
            <Button
              type="button"
              variant="secondary"
              disabled={saving}
              onClick={closeModal}
            >
              Batal
            </Button>
            <Button
              type="button"
              disabled={saving || !name.trim()}
              onClick={() => void saveNewBrand()}
            >
              {saving ? "Menyimpan…" : "Simpan"}
            </Button>
          </>
        }
      >
        <p className="mb-4 text-sm text-slate-500">
          Brand langsung terpilih setelah disimpan.
        </p>
        <FormField
          label="Nama brand"
          htmlFor="new-product-brand"
          error={error ?? undefined}
        >
          <input
            id="new-product-brand"
            value={name}
            disabled={saving}
            onChange={(event) => setName(event.target.value)}
            className="admin-field-control"
          />
        </FormField>
      </AdminDialog>
    </div>
  );
}
