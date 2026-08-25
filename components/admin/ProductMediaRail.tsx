"use client";

import { useEffect, useRef, useState } from "react";
import type React from "react";
import ProductVideoDraft, { type ProductVideoDraftHandle } from "./ProductVideoDraft";
import { canRemoveImage, removeImageAt, reorderImages } from "@/lib/product/product-media";
import { uploadProductImageFiles } from "../MultiImageUpload";
export { canRemoveImage, removeImageAt } from "@/lib/product/product-media";

export type ProductVideoDraftValue = {
  videoGuid?: string | null;
  videoStatus?: string | null;
  videoThumbnailUrl?: string | null;
  videoDurationSec?: number | null;
};
export type ProductVideoIntent = "keep" | "remove" | "replace";

export function ProductMediaRail({ images, video, onImagesChange, onVideoIntentChange, videoDraftRef }: {
  images: string[];
  video?: ProductVideoDraftValue | null;
  onImagesChange(images: string[]): void;
  onVideoIntentChange(intent: ProductVideoIntent): void;
  videoDraftRef?: React.Ref<ProductVideoDraftHandle>;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const videoRef = useRef<ProductVideoDraftHandle>(null);
  const activeVideoRef = (videoDraftRef ?? videoRef) as React.RefObject<ProductVideoDraftHandle>;
  const [preview, setPreview] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [draggedIndex, setDraggedIndex] = useState<number | null>(null);
  useEffect(() => { if (!preview) return; const close = (event: KeyboardEvent) => { if (event.key === "Escape") setPreview(null); }; window.addEventListener("keydown", close); return () => window.removeEventListener("keydown", close); }, [preview]);

  async function addFiles(files: FileList | null) {
    if (!files) return;
    const incoming = Array.from(files).slice(0, 9 - images.length);
    const result = await uploadProductImageFiles(incoming, 9 - images.length);
    const urls = result.uploaded;
    // Sebutkan file + alasannya. Pesan lama ("Sebagian foto gagal di-upload.")
    // tidak menyebut apa pun, jadi mustahil dibedakan antara file kebesaran,
    // format ditolak, atau server sedang sibuk.
    setError(result.errors.length ? result.errors.join(" · ") : null);
    onImagesChange([...images, ...urls].slice(0, 9));
  }

  return <div className="space-y-3">
    <div className="flex flex-wrap gap-2">
      {images.map((url, index) => <div key={`${url}-${index}`} draggable onDragStart={() => setDraggedIndex(index)} onDragOver={(event) => event.preventDefault()} onDrop={() => { if (draggedIndex !== null) onImagesChange(reorderImages(images, draggedIndex, index)); setDraggedIndex(null); }} onDragEnd={() => setDraggedIndex(null)} className={`group relative h-20 w-20 overflow-hidden rounded-xl border bg-zinc-50 ${draggedIndex === index ? "border-natalo-500 opacity-60" : "border-zinc-200"}`}>
        <button type="button" aria-label={`Preview foto ${index + 1}. Seret untuk mengubah urutan`} onClick={() => setPreview(url)} className="h-full w-full cursor-grab active:cursor-grabbing">
        <img src={url} alt={`Foto ${index + 1}`} draggable={false} className="h-full w-full object-cover" />
        {index === 0 ? <span className="absolute bottom-0 inset-x-0 bg-zinc-950/75 py-0.5 text-[10px] font-semibold text-white">Cover</span> : null}
        </button><button type="button" aria-label={index === 0 ? "Hapus foto cover" : `Hapus foto ${index + 1}`} onClick={() => { if (canRemoveImage(images)) onImagesChange(removeImageAt(images, index)); }} className="absolute right-1 top-1 rounded-full bg-white/95 px-1.5 text-xs font-bold text-zinc-700 shadow">×</button>
      </div>)}
      {images.length < 9 ? <button type="button" aria-label="Tambah foto" onClick={() => fileRef.current?.click()} className="flex h-20 w-20 flex-col items-center justify-center rounded-xl border border-dashed border-zinc-300 text-xs text-zinc-500">＋<span>{images.length}/9</span></button> : null}
    </div>
    <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp,image/gif" multiple className="hidden" onChange={(event) => { void addFiles(event.target.files); event.currentTarget.value = ""; }} />
    <div className="flex items-center gap-2">
      <button type="button" aria-label="Preview atau edit video" onClick={() => activeVideoRef.current?.openPicker()} className="h-20 w-20 overflow-hidden rounded-xl border border-zinc-200 bg-zinc-50 p-1">
        {video?.videoThumbnailUrl ? <img src={video.videoThumbnailUrl} alt="Video produk" className="h-full w-full rounded-lg object-cover" /> : <div className="flex h-full items-center justify-center text-xs text-zinc-500">Video</div>}
      </button>
      <div className="min-w-0 flex-1"><ProductVideoDraft ref={activeVideoRef} onIntentChange={onVideoIntentChange} initial={video ? { videoGuid: video.videoGuid ?? null, videoStatus: video.videoStatus ?? null, videoThumbnailUrl: video.videoThumbnailUrl ?? null, videoDurationSec: video.videoDurationSec ?? null } : undefined} /></div>
    </div>
    {error ? <p className="text-xs text-red-600">{error}</p> : null}
    {preview ? <div role="dialog" aria-modal="true" aria-label="Preview foto" className="fixed inset-0 z-50 flex items-center justify-center bg-zinc-950/70 p-6" onClick={() => setPreview(null)}><button type="button" aria-label="Tutup preview" onClick={() => setPreview(null)} className="absolute right-4 top-4 rounded-full bg-white px-3 py-1 text-lg">×</button><img src={preview} alt="Preview foto" className="max-h-full max-w-full rounded-xl object-contain" /></div> : null}
  </div>;
}

export default ProductMediaRail;
