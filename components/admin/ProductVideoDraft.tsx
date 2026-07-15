"use client";

import { forwardRef, useImperativeHandle, useRef, useState } from "react";
import { Button, DangerButton, useAdminToast } from "@/components/admin/ui";
import { readVideoMetadata } from "@/lib/feed/video-thumbnail";
import { formatFileSize } from "@/lib/feed/video-config";
import { trimVideo } from "@/lib/feed/video-trimmer";
import { uploadToBunnyViaTus, type BunnyTusCredentials } from "@/lib/feed/tus-upload";

const MAX_SOURCE = 200 * 1024 * 1024;
const MIN_DURATION = 10;
const MAX_DURATION = 60;

export type PreparedVideo = { file: File; durationSec: number; trimStartSec: number; trimEndSec: number };
export type ProductVideoDraftHandle = {
  prepareForSave(): Promise<PreparedVideo | null>;
  commitAfterProductSave(productId: string): Promise<void>;
  discardPendingCreation(): Promise<void>;
  getDraftState(): { hasPendingVideo: boolean; removeRequested: boolean };
};
type Initial = { videoGuid?: string | null; videoStatus: string | null; videoThumbnailUrl: string | null; videoDurationSec: number | null };

export const ProductVideoDraft = forwardRef<ProductVideoDraftHandle, { productId?: string; initial?: Initial }>(function ProductVideoDraft({ productId, initial }, ref) {
  const { show } = useAdminToast();
  const inputRef = useRef<HTMLInputElement>(null);
  const [picked, setPicked] = useState<PreparedVideo | null>(null);
  const [existingGuid, setExistingGuid] = useState(initial?.videoGuid ?? null);
  const [existingStatus, setExistingStatus] = useState(initial?.videoStatus ?? null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [removeRequested, setRemoveRequested] = useState(false);
  const [trimStartSec, setTrimStartSec] = useState(0);
  const [trimEndSec, setTrimEndSec] = useState(0);
  const [sourceDurationSec, setSourceDurationSec] = useState(0);

  async function pick(file: File | null) {
    setError(null); setPicked(null);
    if (!file) return;
    setRemoveRequested(false);
    if (!file.type.startsWith("video/")) return setError("Format video belum didukung. Pilih MP4/MOV/WebM.");
    if (file.size > MAX_SOURCE) return setError(`Ukuran video melebihi ${formatFileSize(MAX_SOURCE)}.`);
    try {
      const meta = await readVideoMetadata(file);
      if (meta.durationSec < MIN_DURATION) return setError(`Durasi minimal ${MIN_DURATION} detik.`);
      const end = Math.min(meta.durationSec, MAX_DURATION);
      setSourceDurationSec(meta.durationSec);
      setTrimStartSec(0); setTrimEndSec(end);
      setPicked({ file, durationSec: Math.round(end), trimStartSec: 0, trimEndSec: end });
    } catch { setError("Video tidak bisa dibaca. Coba pilih file lain."); }
  }

  useImperativeHandle(ref, () => ({
    async prepareForSave() { return picked; },
    async commitAfterProductSave(id: string) {
      if (!picked) return;
      setBusy(true);
      let createdGuid: string | null = null;
      try {
        const provision = await fetch(`/api/admin/products/${id}/video`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ videoDurationSec: picked.durationSec }) });
        const data = await provision.json().catch(() => ({})) as { videoGuid?: string; tus?: BunnyTusCredentials; error?: string };
        if (!provision.ok || !data.videoGuid || !data.tus) throw new Error(data.error ?? "Gagal menyiapkan upload.");
        createdGuid = data.videoGuid;
        let blob: Blob = picked.file;
        const wantsTrim = picked.trimStartSec > 0.1 || picked.trimEndSec < sourceDurationSec - 0.1;
        if (wantsTrim) blob = await trimVideo(picked.file, { trimStartSec: picked.trimStartSec, trimDurationSec: picked.trimEndSec - picked.trimStartSec });
        await uploadToBunnyViaTus({ file: blob, credentials: data.tus, filetype: picked.file.type || "video/mp4", title: `product-${id}` });
        const done = await fetch(`/api/admin/products/${id}/video`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ videoGuid: createdGuid, videoDurationSec: picked.durationSec }) });
        if (!done.ok) throw new Error("Gagal menandai video sebagai diproses.");
        setExistingGuid(createdGuid); setExistingStatus("processing"); setPicked(null); show("Video diunggah dan sedang diproses.");
      } catch (err) {
        setError(err instanceof Error ? err.message : "Upload video gagal.");
        if (id && createdGuid) await fetch(`/api/admin/products/${id}/video`, { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ videoGuid: createdGuid }) }).catch(() => undefined);
        throw err;
      } finally { setBusy(false); }
    },
    async discardPendingCreation() { setPicked(null); },
    getDraftState() { return { hasPendingVideo: Boolean(picked), removeRequested }; },
  }), [picked, productId, show, sourceDurationSec, removeRequested]);

  async function remove() {
    // Draft intent only: the parent decides whether deletion is committed.
    setRemoveRequested(true); setExistingGuid(null); setExistingStatus(null); setPicked(null);
  }

  return <div className="space-y-2">
    <input ref={inputRef} type="file" accept="video/mp4,video/quicktime,video/webm,video/*" className="hidden" onChange={(e) => void pick(e.target.files?.[0] ?? null)} />
    {existingGuid && !picked ? <div className="flex items-center justify-between rounded-xl border p-3"><span className="text-sm">Video {existingStatus ?? "tersedia"}</span><span className="flex gap-2"><Button type="button" size="sm" variant="secondary" onClick={() => inputRef.current?.click()}>Ganti</Button><DangerButton type="button" size="sm" onClick={() => void remove()}>Hapus</DangerButton></span></div> : null}
    {!existingGuid && !picked ? <Button type="button" variant="secondary" onClick={() => inputRef.current?.click()}>Tambah Video Produk</Button> : null}
    {picked ? <div className="rounded-xl border p-3 text-sm"><p className="font-semibold">{picked.file.name} · {formatFileSize(picked.file.size)} · {picked.durationSec} dtk</p><label className="mt-2 block text-xs">Mulai {trimStartSec} dtk<input type="range" min={0} max={Math.max(0, trimEndSec - MIN_DURATION)} value={trimStartSec} onChange={(e) => { const v = Number(e.target.value); setTrimStartSec(v); setPicked({ ...picked, trimStartSec: v }); }} className="w-full" /></label><label className="block text-xs">Selesai {trimEndSec} dtk<input type="range" min={trimStartSec + MIN_DURATION} max={Math.min(sourceDurationSec, MAX_DURATION)} value={trimEndSec} onChange={(e) => { const v = Number(e.target.value); setTrimEndSec(v); setPicked({ ...picked, trimEndSec: v, durationSec: Math.round(v - trimStartSec) }); }} className="w-full" /></label><p className="mt-2 text-xs text-zinc-500">Video akan diunggah saat produk disimpan.</p><Button type="button" variant="ghost" disabled={busy} onClick={() => setPicked(null)}>Batal</Button></div> : null}
    {error ? <p className="rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">{error}</p> : null}
  </div>;
});

export default ProductVideoDraft;
