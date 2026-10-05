"use client";

import { useEffect, useRef, useState } from "react";
import { uploadAdminImage } from "@/lib/admin-image-upload";
import { AdminDialog } from "./ui/AdminDialog";
import { Button } from "./ui";

export function VariantPhotoField({ imageUrl, label, onChange, onBusyChange }: {
  imageUrl: string; label: string; onChange(url: string): void; onBusyChange?(busy: boolean): void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const imageRef = useRef<HTMLImageElement>(null);
  const drag = useRef<{ x: number; y: number; left: number; top: number } | null>(null);
  const busyRef = useRef(false);
  const [mode, updateMode] = useState<"preview" | "edit" | "remove">("preview");
  const [dialogOpen, setDialogOpen] = useState(false);
  function setMode(next: "preview" | "edit" | "remove" | null) {
    if (next !== null) updateMode(next);
    setDialogOpen(next !== null);
  }
  const [source, setSource] = useState("");
  const [editorRevision, setEditorRevision] = useState(0);
  const [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [zoom, setZoom] = useState(1);
  const [rotation, setRotation] = useState(0);
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const [ratio, setRatio] = useState(1);
  useEffect(() => () => { if (source.startsWith("blob:")) URL.revokeObjectURL(source); }, [source]);
  function openEditor(src: string) {
    setEditorRevision(value => value + 1);
    setSource(src); setReady(false); setError(""); setZoom(1); setRotation(0); setPosition({ x: 0, y: 0 }); setMode("edit");
  }
  const width = ratio >= 1 ? 100 : ratio * 100;
  const height = ratio >= 1 ? 100 / ratio : 100;
  const transform = `translate(${position.x}%, ${position.y}%) rotate(${rotation}deg) scale(${zoom})`;
  async function savePhoto() {
    if (!ready || busyRef.current || !imageRef.current) return;
    busyRef.current = true; setBusy(true); onBusyChange?.(true); setError("");
    try {
      const image = imageRef.current;
      const size = Math.min(1200, Math.max(image.naturalWidth, image.naturalHeight));
      const canvas = document.createElement("canvas"); canvas.width = canvas.height = size;
      const context = canvas.getContext("2d");
      if (!context) throw new Error("Foto tidak dapat diproses.");
      context.fillStyle = "#fff"; context.fillRect(0, 0, size, size);
      // CSS translation is relative to the fitted image, matching canvas export.
      const w = size * width / 100; const h = size * height / 100;
      context.translate(size / 2 + position.x * w / 100, size / 2 + position.y * h / 100);
      context.rotate(rotation * Math.PI / 180); context.scale(zoom, zoom);
      context.drawImage(image, -w / 2, -h / 2, w, h);
      const blob = await new Promise<Blob>((resolve, reject) => canvas.toBlob(value => value ? resolve(value) : reject(new Error("Foto tidak dapat diproses.")), "image/jpeg", .88));
      const url = await uploadAdminImage(new File([blob], "variant-photo.jpg", { type: "image/jpeg" }));
      onChange(url); setMode(null);
    } catch {
      setError("Foto gagal disimpan. Foto sebelumnya tetap tersedia. Coba lagi atau pilih foto dari perangkat.");
    } finally { busyRef.current = false; setBusy(false); onBusyChange?.(false); }
  }
  const cropImage = (preview: boolean) => <div className="relative flex aspect-square items-center justify-center overflow-hidden rounded-lg border border-zinc-200 bg-white">
    <img key={editorRevision} ref={preview ? undefined : imageRef} src={source} crossOrigin="anonymous" alt={preview ? `Hasil crop ${label}` : label}
      style={{ width: `${width}%`, height: `${height}%`, transform, maxWidth: "none" }} className="pointer-events-none shrink-0 object-contain"
      onLoad={preview ? undefined : e => { setRatio(e.currentTarget.naturalWidth / e.currentTarget.naturalHeight); setReady(true); }}
      onError={preview ? undefined : () => { setReady(false); setError("Foto tidak dapat dimuat untuk diedit. Pilih foto dari perangkat."); }} />
    {!preview && <div aria-hidden="true" className="pointer-events-none absolute inset-0 grid grid-cols-3 grid-rows-3 border-2 border-blue-500">{Array.from({ length: 9 }, (_, i) => <span key={i} className="border border-white/40" />)}</div>}
  </div>;
  return <div className="variant-photo-field">
    <button type="button" className={`variant-photo-thumbnail ${imageUrl ? "" : "is-empty"}`} onClick={() => imageUrl ? setMode("preview") : fileRef.current?.click()} aria-label={`${imageUrl ? "Pratinjau" : "Tambah"} foto ${label}`}>
      {imageUrl ? <img src={imageUrl} alt={label} /> : <span aria-hidden="true">+</span>}
    </button>
    {imageUrl && <div className="variant-photo-tools">
      <button type="button" onClick={() => openEditor(imageUrl)} aria-label={`Edit foto ${label}`} title="Edit foto"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="m16 3 5 5-12 12-6 1 1-6Z" /></svg></button>
      <button type="button" onClick={() => setMode("remove")} aria-label={`Hapus foto ${label}`} title="Hapus foto"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7" /></svg></button>
    </div>}
    <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={e => { const file = e.target.files?.[0]; e.target.value = ""; if (file) openEditor(URL.createObjectURL(file)); }} />
    <AdminDialog open={dialogOpen} title={mode === "remove" ? "Hapus foto varian?" : mode === "preview" ? `Foto ${label}` : `Ubah foto ${label}`} onClose={() => { if (!busyRef.current) setMode(null); }} busy={busy}
      footer={mode === "edit" ? <><Button type="button" variant="secondary" disabled={busy} onClick={() => fileRef.current?.click()}>Ganti foto</Button><Button type="button" variant="secondary" disabled={busy} onClick={() => setMode(null)}>Batal</Button><Button type="button" disabled={busy || !ready} onClick={() => void savePhoto()}>{busy ? "Menyimpan…" : "Simpan foto"}</Button></> : mode === "remove" ? <><Button type="button" variant="secondary" onClick={() => setMode(null)}>Batal</Button><Button type="button" onClick={() => { onChange(""); setMode(null); }}>Hapus foto</Button></> : <Button type="button" onClick={() => openEditor(imageUrl)}>Edit foto</Button>}>
      {mode === "preview" && <img src={imageUrl} alt={label} className="mx-auto max-h-[60vh] w-full object-contain" />}
      {mode === "remove" && <p>Foto {label} akan dilepas dari varian. Perubahan berlaku setelah produk disimpan.</p>}
      {mode === "edit" && <div>
        <div className="grid gap-5 sm:grid-cols-[minmax(0,1fr)_110px]">
          <div role="group" aria-label="Geser foto untuk mengatur crop" tabIndex={0} className="touch-none cursor-move rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-600"
            onKeyDown={e => { if (busy) return; const move = { ArrowLeft: [-2, 0], ArrowRight: [2, 0], ArrowUp: [0, -2], ArrowDown: [0, 2] }[e.key]; if (move) { e.preventDefault(); setPosition(p => ({ x: Math.max(-100, Math.min(100, p.x + move[0])), y: Math.max(-100, Math.min(100, p.y + move[1])) })); } }}
            onPointerDown={e => { if (busy) return; e.currentTarget.setPointerCapture(e.pointerId); drag.current = { x: e.clientX, y: e.clientY, left: position.x, top: position.y }; }}
            onPointerMove={e => { const d = drag.current; if (!d || busy) return; const rect = e.currentTarget.getBoundingClientRect(); setPosition({ x: Math.max(-100, Math.min(100, d.left + (e.clientX - d.x) / (rect.width * width / 100) * 100)), y: Math.max(-100, Math.min(100, d.top + (e.clientY - d.y) / (rect.height * height / 100) * 100)) }); }} onPointerUp={() => { drag.current = null; }} onPointerCancel={() => { drag.current = null; }}>{cropImage(false)}</div>
          <div className="hidden sm:block"><p className="mb-2 text-xs text-zinc-500">Pratinjau</p>{cropImage(true)}</div>
        </div>
        <div className="mt-4 flex flex-wrap items-center gap-3"><label className="flex min-w-0 flex-1 items-center gap-3 text-sm">Zoom<input aria-label="Zoom foto" type="range" min="1" max="3" step=".05" value={zoom} disabled={busy} onChange={e => setZoom(Number(e.target.value))} className="min-w-0 flex-1" /></label><Button type="button" variant="secondary" disabled={busy} onClick={() => setRotation(r => (r + 90) % 360)}>Putar</Button><Button type="button" variant="secondary" disabled={busy} onClick={() => { setZoom(1); setRotation(0); setPosition({ x: 0, y: 0 }); }}>Atur ulang</Button></div>
        {error && <p role="alert" className="mt-3 text-sm text-red-700">{error}</p>}
      </div>}
    </AdminDialog>
  </div>;
}
