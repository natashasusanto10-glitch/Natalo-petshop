"use client";

import { useRef, useState } from "react";

interface ImageUploadProps {
  name: string;
  defaultValue?: string;
  label?: string;
}

export function ImageUpload({ name, defaultValue = "", label = "Gambar produk" }: ImageUploadProps) {
  const [url, setUrl] = useState(defaultValue);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  async function handleFile(file: File) {
    setError("");
    setUploading(true);

    const formData = new FormData();
    formData.append("file", file);

    const res = await fetch("/api/admin/upload", {
      method: "POST",
      body: formData,
    });

    const data = await res.json();
    setUploading(false);

    if (!res.ok) {
      setError(data.error || "Gagal upload");
      return;
    }

    setUrl(data.url);
  }

  return (
    <div>
      <label className="block text-sm font-medium text-zinc-700">{label}</label>

      {/* Hidden input untuk submit form (sebagai imageUrl) */}
      <input type="hidden" name={name} value={url} />

      <div className="mt-1 flex items-start gap-4">
        {/* Preview */}
        <div className="flex h-28 w-28 shrink-0 items-center justify-center overflow-hidden rounded-2xl border border-dashed border-zinc-300 bg-zinc-50">
          {url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={url} alt="preview" className="h-full w-full object-cover" />
          ) : (
            <span className="text-3xl text-zinc-300">🖼️</span>
          )}
        </div>

        <div className="flex-1 space-y-2">
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => fileRef.current?.click()}
              disabled={uploading}
              className="rounded-full bg-zinc-950 px-4 py-2 text-sm font-bold text-white disabled:opacity-50"
            >
              {uploading ? "Mengupload..." : url ? "Ganti gambar" : "Pilih gambar"}
            </button>

            {url && (
              <button
                type="button"
                onClick={() => setUrl("")}
                className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-bold"
              >
                Hapus
              </button>
            )}
          </div>

          <input
            ref={fileRef}
            type="file"
            accept="image/jpeg,image/png,image/webp,image/gif"
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0];
              if (file) handleFile(file);
              e.target.value = ""; // reset agar bisa pilih file yang sama
            }}
          />

          <p className="text-xs text-zinc-400">JPG, PNG, WEBP, atau GIF. Maks 5 MB.</p>

          {/* Manual URL input as fallback */}
          <input
            type="text"
            value={url}
            onChange={(e) => setUrl(e.target.value)}
            placeholder="Atau tempel URL gambar"
            className="block w-full rounded-xl border border-zinc-200 px-3 py-2 text-xs outline-none focus:border-zinc-600"
          />

          {error && <p className="text-xs text-red-500">{error}</p>}
        </div>
      </div>
    </div>
  );
}
