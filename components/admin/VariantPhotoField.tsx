"use client";

import { useEffect, useRef, useState } from "react";
import { MAX_SIZE_MB, uploadAdminImage, uploadOne } from "@/lib/admin-image-upload";
import { AdminDialog } from "./ui/AdminDialog";
import { Button } from "./ui";

const PHOTO_LOAD_TIMEOUT_MS = 10_000;

async function waitForUploadedPhoto(url: string): Promise<string> {
  // A successful storage upload does not guarantee the CDN is readable yet.
  for (let attempt = 0; attempt < 3; attempt++) {
    const candidate = new URL(url);
    // Only bypass cached failures for public UploadThing URLs, never signed URLs.
    if (attempt > 0 && !candidate.search && (candidate.hostname.endsWith(".ufs.sh") || candidate.hostname === "utfs.io")) {
      candidate.searchParams.set("photoCheck", `${Date.now()}-${attempt}`);
    }
    try {
      await new Promise<void>((resolve, reject) => {
        const image = new Image();
        const finish = (error?: Error) => {
          clearTimeout(timeout);
          image.onload = image.onerror = null;
          if (error) reject(error); else resolve();
        };
        const timeout = setTimeout(() => {
          finish(new Error("Foto belum dapat dimuat."));
          image.removeAttribute("src");
        }, PHOTO_LOAD_TIMEOUT_MS);
        image.onload = () => image.naturalWidth > 0 ? finish() : finish(new Error("Foto tidak valid."));
        image.onerror = () => finish(new Error("Foto belum dapat dimuat."));
        image.src = candidate.href;
      });
      return candidate.href;
    } catch (error) {
      if (attempt === 2) throw error;
      await new Promise(resolve => setTimeout(resolve, 500 * (attempt + 1)));
    }
  }
  throw new Error("Foto belum dapat dimuat.");
}

export function VariantPhotoField({ imageUrl, label, onChange, onBusyChange }: {
  imageUrl: string; label: string; onChange(url: string): void; onBusyChange?(busy: boolean): void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const pickerIntent = useRef<"upload" | "edit">("upload");
  const directUpload = useRef<{ file: File; url?: string } | null>(null);
  const imageRef = useRef<HTMLImageElement>(null);
  const drag = useRef<{ x: number; y: number; left: number; top: number } | null>(null);
  const busyRef = useRef(false);
  const savedUpload = useRef<{ cropKey: string; url: string } | null>(null);
  const preparedPhoto = useRef<{ cropKey: string; file: File } | null>(null);
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
  const [progress, setProgress] = useState("");
  const [verifiedPhoto, setVerifiedPhoto] = useState<{ url: string; displayUrl: string } | null>(null);
  const [error, setError] = useState("");
  const [uploadError, setUploadError] = useState("");
  const [uploadPreview, setUploadPreview] = useState("");
  const [zoom, setZoom] = useState(1);
  const [rotation, setRotation] = useState(0);
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const [ratio, setRatio] = useState(1);
  const [failedImageUrl, setFailedImageUrl] = useState<string | null>(null);
  const imageFailed = Boolean(imageUrl) && failedImageUrl === imageUrl;
  useEffect(() => () => { if (source.startsWith("blob:")) URL.revokeObjectURL(source); }, [source]);
  useEffect(() => () => { if (uploadPreview) URL.revokeObjectURL(uploadPreview); }, [uploadPreview]);
  function choosePhoto(intent: "upload" | "edit") {
    if (busyRef.current) return;
    pickerIntent.current = intent;
    fileRef.current?.click();
  }
  async function uploadSelectedPhoto(file: File, retry = false) {
    if (busyRef.current) return;
    if (!retry) directUpload.current = { file };
    const selected = directUpload.current;
    if (!selected) return;
    busyRef.current = true;
    setBusy(true); onBusyChange?.(true); setUploadError("");
    setUploadPreview(URL.createObjectURL(selected.file));
    let phase: "upload" | "load" = "upload";
    try {
      setProgress("Mengunggah foto…");
      if (!selected.url) selected.url = await uploadAdminImage(selected.file);
      phase = "load";
      setProgress("Memeriksa foto…");
      const loadedUrl = await waitForUploadedPhoto(selected.url);
      setVerifiedPhoto({ url: selected.url, displayUrl: loadedUrl });
      setFailedImageUrl(null);
      onChange(selected.url);
      directUpload.current = null;
    } catch (cause) {
      const detail = cause instanceof Error ? cause.message : "Koneksi atau server bermasalah.";
      setUploadError(phase === "load"
        ? "Foto sudah diunggah, tetapi belum dapat dimuat. Coba lagi akan memeriksa foto tanpa mengunggah ulang."
        : `Upload gagal: ${detail}. Klik Coba lagi atau pilih foto lain.`);
    } finally {
      setUploadPreview(""); setProgress(""); setBusy(false);
      busyRef.current = false; onBusyChange?.(false);
    }
  }
  function openEditor(src: string) {
    if (busyRef.current) return;
    directUpload.current = null;
    setUploadError("");
    savedUpload.current = null;
    preparedPhoto.current = null;
    setEditorRevision(value => value + 1);
    setSource(src); setReady(false); setError(""); setZoom(1); setRotation(0); setPosition({ x: 0, y: 0 }); setMode("edit");
  }
  function removePhoto() {
    if (busyRef.current) return;
    directUpload.current = null;
    savedUpload.current = null;
    preparedPhoto.current = null;
    setUploadError(""); setError(""); setVerifiedPhoto(null); setFailedImageUrl(null);
    onChange(""); setMode(null);
  }
  const width = ratio >= 1 ? 100 : ratio * 100;
  const height = ratio >= 1 ? 100 / ratio : 100;
  const transform = `translate(${position.x}%, ${position.y}%) rotate(${rotation}deg) scale(${zoom})`;
  const displayUrl = verifiedPhoto?.url === imageUrl ? verifiedPhoto.displayUrl : imageUrl;
  async function savePhoto() {
    if (!ready || busyRef.current || !imageRef.current) return;
    busyRef.current = true; setBusy(true); onBusyChange?.(true); setError("");
    let phase: "process" | "upload" | "load" = "process";
    try {
      const cropKey = JSON.stringify([editorRevision, zoom, rotation, position.x, position.y, ratio]);
      setProgress("Memproses foto…");
      if (preparedPhoto.current?.cropKey !== cropKey && savedUpload.current?.cropKey !== cropKey) {
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
        preparedPhoto.current = { cropKey, file: new File([blob], "variant-photo.jpg", { type: "image/jpeg" }) };
      }
      phase = "upload";
      setProgress("Mengunggah foto…");
      if (savedUpload.current?.cropKey !== cropKey) {
        const prepared = preparedPhoto.current;
        if (!prepared || prepared.cropKey !== cropKey) throw new Error("Hasil crop tidak tersedia. Pilih foto kembali.");
        // Crop export is already a resized JPEG. Avoid a second encode when
        // it fits the upload limit; keep compression for oversized exports.
        const url = prepared.file.size <= MAX_SIZE_MB * 1024 * 1024
          ? await uploadOne(prepared.file)
          : await uploadAdminImage(prepared.file);
        savedUpload.current = { cropKey, url };
      }
      const url = savedUpload.current.url;
      phase = "load";
      setProgress("Memeriksa foto…");
      const loadedUrl = await waitForUploadedPhoto(url);
      setVerifiedPhoto({ url, displayUrl: loadedUrl });
      setFailedImageUrl(null);
      onChange(url); setMode(null);
    } catch (cause) {
      if (phase === "load") {
        setError("Foto sudah diunggah, tetapi belum dapat dimuat. Klik Simpan foto untuk memeriksa kembali tanpa mengunggah ulang. Foto varian belum diganti.");
      } else if (phase === "upload") {
        const detail = cause instanceof Error ? cause.message : "Koneksi atau server bermasalah.";
        setError(`Upload gagal: ${detail}. Hasil crop tetap tersedia untuk dicoba kembali.`);
      } else {
        setError("Foto gagal diproses. Pilih foto dari perangkat kembali, lalu coba simpan. Foto varian belum diganti.");
      }
    } finally { busyRef.current = false; setBusy(false); setProgress(""); onBusyChange?.(false); }
  }
  const cropImage = (preview: boolean) => <div className="relative flex aspect-square items-center justify-center overflow-hidden rounded-lg border border-zinc-200 bg-white">
    <img key={editorRevision} ref={preview ? undefined : imageRef} src={source} crossOrigin="anonymous" alt={preview ? `Hasil crop ${label}` : label}
      style={{ width: `${width}%`, height: `${height}%`, transform, maxWidth: "none" }} className="pointer-events-none shrink-0 object-contain"
      onLoad={preview ? undefined : e => { setRatio(e.currentTarget.naturalWidth / e.currentTarget.naturalHeight); setReady(true); }}
      onError={preview ? undefined : () => { setReady(false); setError("Foto tidak dapat dimuat untuk diedit. Pilih foto dari perangkat."); }} />
    {!preview && <div aria-hidden="true" className="pointer-events-none absolute inset-0 grid grid-cols-3 grid-rows-3 border-2 border-blue-500">{Array.from({ length: 9 }, (_, i) => <span key={i} className="border border-white/40" />)}</div>}
  </div>;
  return <div className="variant-photo-field">
    <button type="button" disabled={busy} aria-busy={busy} className={`variant-photo-thumbnail ${imageUrl ? "" : "is-empty"}`} onClick={() => imageUrl && !imageFailed ? setMode("preview") : choosePhoto("upload")} aria-label={`${imageFailed ? "Ganti" : imageUrl ? "Pratinjau" : "Tambah"} foto ${label}`}>
      {uploadPreview ? <img src={uploadPreview} alt={`Mengunggah foto ${label}`} className="opacity-60" /> : imageFailed ? <span className="text-xs leading-tight text-red-700">Gagal muat<br />Ganti foto</span> : imageUrl ? <img key={displayUrl} src={displayUrl} alt={label} onError={() => setFailedImageUrl(imageUrl)} /> : <span aria-hidden="true">+</span>}
    </button>
    {imageUrl && <div className="variant-photo-tools" style={{ opacity: 1, pointerEvents: "auto", transform: "none" }}>
      <button type="button" disabled={busy} onClick={() => openEditor(displayUrl)} aria-label={`Edit foto ${label}`} title="Edit foto"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="m16 3 5 5-12 12-6 1 1-6Z" /></svg></button>
      <button type="button" disabled={busy} onClick={() => setMode("remove")} aria-label={`Hapus foto ${label}`} title="Hapus foto"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7" /></svg></button>
    </div>}
    <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={e => { const file = e.target.files?.[0]; e.target.value = ""; if (file) { if (pickerIntent.current === "edit") openEditor(URL.createObjectURL(file)); else void uploadSelectedPhoto(file); } }} />
    {!dialogOpen && busy && <p role="status" aria-live="polite" className="text-xs text-blue-700">{progress}</p>}
    {!dialogOpen && uploadError && <div>
      <p role="alert" className="mt-2 text-xs text-red-700">{uploadError}</p>
      <button type="button" disabled={busy} className="mt-1 text-xs font-medium text-blue-700 underline" onClick={() => { const selected = directUpload.current; if (selected) void uploadSelectedPhoto(selected.file, true); }}>Coba lagi</button>
      <button type="button" disabled={busy} className="ml-2 text-xs text-blue-700 underline" onClick={() => choosePhoto("upload")}>Pilih foto lain</button>
    </div>}
    <AdminDialog open={dialogOpen} title={mode === "remove" ? "Hapus foto varian?" : mode === "preview" ? `Foto ${label}` : `Ubah foto ${label}`} onClose={() => { if (!busyRef.current) setMode(null); }} busy={busy}
      footer={mode === "edit" ? <><Button type="button" variant="secondary" disabled={busy} onClick={() => choosePhoto("edit")}>Ganti foto</Button><Button type="button" variant="secondary" disabled={busy} onClick={() => setMode(null)}>Batal</Button><Button type="button" disabled={busy || !ready} onClick={() => void savePhoto()}>{busy ? "Menyimpan…" : "Simpan foto"}</Button></> : mode === "remove" ? <><Button type="button" variant="secondary" onClick={() => setMode(null)}>Batal</Button><Button type="button" onClick={removePhoto}>Hapus foto</Button></> : <Button type="button" disabled={busy} onClick={() => openEditor(displayUrl)}>Edit foto</Button>}>
      {mode === "preview" && <img src={displayUrl} alt={label} className="mx-auto max-h-[60vh] w-full object-contain" />}
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
        {busy && <p role="status" aria-live="polite" className="mt-3 text-sm text-blue-700">{progress}</p>}
        {error && <p role="alert" className="mt-3 text-sm text-red-700">{error}</p>}
      </div>}
    </AdminDialog>
  </div>;
}
