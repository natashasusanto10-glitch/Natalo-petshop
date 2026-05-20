"use client";

import { useEffect, useRef, useState } from "react";

interface Props {
  /** Nama field hidden input untuk submit. Akan kirim 1 input per gambar. */
  name: string;
  /** Default URL gambar yg sudah ada saat edit. Index 0 = thumbnail utama. */
  defaultValue?: string[];
  label?: string;
  /** Maksimum jumlah gambar. Default 5. */
  max?: number;
  /**
   * Optional callback yang fire setiap kali list URL berubah. Dipakai
   * client form yang submit via fetch (bukan form action) — supaya
   * parent bisa baca state image. Tanpa ini, component tetap berfungsi
   * via hidden inputs (dipakai oleh form server action lama).
   */
  onChange?: (urls: string[]) => void;
}

const MAX_SIZE_MB = 2;

/**
 * Upload 1–{max} gambar ke UploadThing via /api/admin/upload.
 * - Gambar pertama jadi thumbnail utama (akan disimpan ke product.imageUrl).
 * - Sisa gambar masuk ke product.gallery (dipakai di carousel detail).
 * - Tiap gambar maks 2 MB.
 * - Support drag & drop reorder antar slot (HTML5 native, no library).
 *   User bisa geser foto dari slot manapun ke slot manapun untuk
 *   mengubah urutan (mis. pindahkan foto #4 ke #1 jadi cover).
 */
export function MultiImageUpload({
  name,
  defaultValue = [],
  label = "Gambar produk",
  max = 5,
  onChange,
}: Props) {
  const [urls, setUrls] = useState<string[]>(defaultValue);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState("");
  const [dragIndex, setDragIndex] = useState<number | null>(null);
  const [dragOverIndex, setDragOverIndex] = useState<number | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  // Fire onChange callback tiap urls berubah. Pattern aman dari render
  // loop karena setUrls dipanggil dari event handler, bukan tiap render.
  useEffect(() => {
    onChange?.(urls);
  }, [urls, onChange]);

  async function handleFiles(files: FileList) {
    setError("");
    if (urls.length >= max) {
      setError(`Maksimal ${max} gambar.`);
      return;
    }

    const remaining = max - urls.length;
    const incoming = Array.from(files).slice(0, remaining);
    if (files.length > remaining) {
      setError(`Hanya ${remaining} gambar yg ditambahkan — sisa terlewat (maks ${max}).`);
    }

    setUploading(true);

    const uploaded: string[] = [];
    for (const file of incoming) {
      if (file.size > MAX_SIZE_MB * 1024 * 1024) {
        setError(`"${file.name}" melebihi ${MAX_SIZE_MB} MB — dilewati.`);
        continue;
      }
      const fd = new FormData();
      fd.append("file", file);
      try {
        const res = await fetch("/api/admin/upload", { method: "POST", body: fd });
        const data = await res.json();
        if (!res.ok) {
          setError(data.error || `Gagal upload "${file.name}"`);
          continue;
        }
        uploaded.push(data.url);
      } catch {
        setError(`Gagal upload "${file.name}"`);
      }
    }

    setUrls((prev) => [...prev, ...uploaded].slice(0, max));
    setUploading(false);
  }

  function removeAt(idx: number) {
    setUrls((prev) => prev.filter((_, i) => i !== idx));
  }

  /** Reorder array: pindahkan item dari `from` ke posisi `to`. */
  function reorder(from: number, to: number) {
    if (from === to) return;
    setUrls((prev) => {
      if (from < 0 || from >= prev.length || to < 0 || to >= prev.length) {
        return prev;
      }
      const next = [...prev];
      const [picked] = next.splice(from, 1);
      next.splice(to, 0, picked);
      return next;
    });
  }

  // ── HTML5 Drag handlers ────────────────────────────────────
  function handleDragStart(idx: number) {
    return (e: React.DragEvent) => {
      setDragIndex(idx);
      // dataTransfer untuk indicate drag operation di Firefox
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", String(idx));
    };
  }
  function handleDragOver(idx: number) {
    return (e: React.DragEvent) => {
      e.preventDefault(); // allow drop
      e.dataTransfer.dropEffect = "move";
      if (dragIndex !== null && dragIndex !== idx) {
        setDragOverIndex(idx);
      }
    };
  }
  function handleDragLeave() {
    setDragOverIndex(null);
  }
  function handleDrop(idx: number) {
    return (e: React.DragEvent) => {
      e.preventDefault();
      if (dragIndex !== null && dragIndex !== idx) {
        reorder(dragIndex, idx);
      }
      setDragIndex(null);
      setDragOverIndex(null);
    };
  }
  function handleDragEnd() {
    setDragIndex(null);
    setDragOverIndex(null);
  }

  const canAdd = urls.length < max;

  return (
    <div>
      <label className="block text-sm font-medium text-zinc-700">{label}</label>
      <p className="mt-0.5 text-xs text-zinc-500">
        1–{max} gambar, masing-masing maks {MAX_SIZE_MB} MB. Gambar pertama
        jadi thumbnail utama. <span className="font-semibold">Geser foto</span> untuk ubah urutan.
      </p>

      {/* Hidden inputs — satu per gambar, dikirim sebagai {name}[] */}
      {urls.map((url, idx) => (
        <input key={idx} type="hidden" name={name} value={url} />
      ))}

      <div className="mt-3 grid grid-cols-3 gap-3 sm:grid-cols-5">
        {urls.map((url, idx) => {
          const isDragging = dragIndex === idx;
          const isDragOver = dragOverIndex === idx && dragIndex !== idx;
          return (
            <div
              key={`${url}-${idx}`}
              draggable
              onDragStart={handleDragStart(idx)}
              onDragOver={handleDragOver(idx)}
              onDragLeave={handleDragLeave}
              onDrop={handleDrop(idx)}
              onDragEnd={handleDragEnd}
              className={`group relative aspect-square cursor-grab overflow-hidden rounded-2xl border bg-zinc-50 transition active:cursor-grabbing ${
                isDragging
                  ? "border-natalo-500 opacity-40 ring-2 ring-natalo-300"
                  : isDragOver
                    ? "border-natalo-600 ring-2 ring-natalo-400"
                    : "border-zinc-200"
              }`}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={url}
                alt={`Gambar ${idx + 1}`}
                className="pointer-events-none h-full w-full object-cover"
                draggable={false}
              />
              {idx === 0 && (
                <span className="absolute left-1.5 top-1.5 rounded-full bg-zinc-950/85 px-2 py-0.5 text-[10px] font-bold text-white">
                  Utama
                </span>
              )}
              {/* Position indicator at top-right */}
              <span className="absolute right-1.5 top-1.5 rounded-full bg-white/90 px-1.5 py-0.5 text-[10px] font-bold text-zinc-700 shadow">
                {idx + 1}
              </span>
              {/* Drag handle hint at center (visible on hover) */}
              <div className="absolute inset-0 flex items-center justify-center opacity-0 transition group-hover:opacity-100">
                <span className="rounded-full bg-zinc-950/70 px-2 py-1 text-[10px] font-bold text-white">
                  ⇅ Geser
                </span>
              </div>
              <div className="absolute inset-x-1 bottom-1 flex justify-end opacity-0 transition group-hover:opacity-100">
                <button
                  type="button"
                  onClick={() => removeAt(idx)}
                  className="rounded-full bg-red-600 px-3 py-1 text-[10px] font-bold text-white shadow"
                >
                  Hapus
                </button>
              </div>
            </div>
          );
        })}

        {canAdd && (
          <button
            type="button"
            onClick={() => fileRef.current?.click()}
            disabled={uploading}
            className="flex aspect-square flex-col items-center justify-center gap-1 rounded-2xl border-2 border-dashed border-zinc-300 bg-zinc-50 text-zinc-400 transition hover:border-zinc-500 hover:text-zinc-600 disabled:opacity-50"
          >
            <span className="text-2xl">{uploading ? "⏳" : "+"}</span>
            <span className="text-[10px] font-bold">
              {uploading ? "Upload..." : `${urls.length}/${max}`}
            </span>
          </button>
        )}
      </div>

      <input
        ref={fileRef}
        type="file"
        accept="image/jpeg,image/png,image/webp,image/gif"
        multiple
        className="hidden"
        onChange={(e) => {
          if (e.target.files && e.target.files.length > 0) {
            handleFiles(e.target.files);
          }
          e.target.value = "";
        }}
      />

      {error && <p className="mt-2 text-xs text-red-500">{error}</p>}
    </div>
  );
}
