"use client";

import { useEffect, useState } from "react";

export function BrandCreateDialog({
  createAction,
}: {
  createAction: (formData: FormData) => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === "Escape" && !saving) setOpen(false);
    }
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [open, saving]);

  async function submit(formData: FormData) {
    setSaving(true);
    try {
      await createAction(formData);
      setOpen(false);
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className="inline-flex min-h-10 items-center justify-center rounded-xl bg-blue-700 px-4 text-sm font-black text-white shadow-sm transition hover:bg-blue-800">
        + Tambah Brand
      </button>
      {open && (
        <div className="fixed inset-0 z-50 grid place-items-center bg-zinc-950/40 p-4 backdrop-blur-sm" role="dialog" aria-modal="true" aria-labelledby="add-brand-title" onMouseDown={(event) => {
          if (event.target === event.currentTarget && !saving) setOpen(false);
        }}>
          <form action={submit} className="w-full max-w-lg rounded-3xl bg-white p-5 shadow-2xl sm:p-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h2 id="add-brand-title" className="text-xl font-black text-zinc-950">Tambah Brand</h2>
                <p className="mt-1 text-sm text-zinc-500">Brand baru ditempatkan setelah urutan utama.</p>
              </div>
              <button type="button" disabled={saving} onClick={() => setOpen(false)} className="grid h-9 w-9 place-items-center rounded-full text-zinc-500 hover:bg-zinc-100" aria-label="Tutup dialog">×</button>
            </div>
            <div className="mt-6 space-y-4">
              <label className="block text-sm font-bold text-zinc-700">
                Nama brand
                <input autoFocus type="text" name="name" placeholder="Contoh: Royal Canin" required className="mt-1.5 block w-full rounded-xl border border-zinc-300 bg-white px-4 py-3 text-sm outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100" />
              </label>
              <label className="inline-flex items-center gap-2 text-sm font-bold text-zinc-700">
                <input type="checkbox" name="isActive" defaultChecked className="h-4 w-4 rounded border-zinc-300 accent-blue-600" />
                Aktif di aplikasi
              </label>
            </div>
            <div className="mt-7 flex justify-end gap-2">
              <button type="button" disabled={saving} onClick={() => setOpen(false)} className="rounded-xl border border-zinc-200 px-4 py-2.5 text-sm font-bold text-zinc-700 hover:bg-zinc-50">Batal</button>
              <button type="submit" disabled={saving} className="rounded-xl bg-blue-700 px-4 py-2.5 text-sm font-black text-white hover:bg-blue-800 disabled:opacity-60">{saving ? "Menyimpan..." : "Tambah Brand"}</button>
            </div>
          </form>
        </div>
      )}
    </>
  );
}
