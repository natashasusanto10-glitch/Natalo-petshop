"use client";

import { useRef, useState } from "react";
import { Button, DangerButton, ConfirmDialog, useAdminToast } from "@/components/admin/ui";
import { readVideoMetadata } from "@/lib/feed/video-thumbnail";
import { formatFileSize } from "@/lib/feed/video-config";
import { trimVideo } from "@/lib/feed/video-trimmer";
import {
  uploadToBunnyViaTus,
  type BunnyTusCredentials,
} from "@/lib/feed/tus-upload";

const MAX_SOURCE = 200 * 1024 * 1024;
const MIN_DURATION = 10;
const MAX_DURATION = 60;
const ACCEPT = "video/mp4,video/quicktime,video/*";

type Initial = {
  videoStatus: string | null;
  videoThumbnailUrl: string | null;
  videoDurationSec: number | null;
};

type Picked = {
  file: File;
  sizeLabel: string;
  width: number;
  height: number;
  durationSec: number;
  qualityLabel: string;
};

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), Math.max(lo, hi));

function qualityLabel(h: number): string {
  if (h >= 1080) return "HD 1080p";
  if (h >= 720) return "HD 720p";
  if (h >= 480) return "SD 480p";
  return `${h}p`;
}

export function ProductVideoUpload({
  productId,
  initial,
}: {
  productId: string;
  initial: Initial;
}) {
  const { show } = useAdminToast();
  const inputRef = useRef<HTMLInputElement>(null);
  const [status, setStatus] = useState<string | null>(initial.videoStatus);
  const [thumb, setThumb] = useState<string | null>(initial.videoThumbnailUrl);
  const [durationSec, setDurationSec] = useState<number | null>(initial.videoDurationSec);

  const [picked, setPicked] = useState<Picked | null>(null);
  const [pickError, setPickError] = useState<string | null>(null);
  // Trim range
  const [trimStart, setTrimStart] = useState(0);
  const [trimEnd, setTrimEnd] = useState(MAX_DURATION);
  const finalDuration = Math.max(0, trimEnd - trimStart);

  const [uploading, setUploading] = useState(false);
  const [progress, setProgress] = useState(0);
  const [stage, setStage] = useState<"" | "trimming" | "uploading">("");
  const [confirmDelete, setConfirmDelete] = useState(false);

  async function onPick(file: File | null) {
    setPickError(null);
    setPicked(null);
    if (!file) return;
    if (!file.type.startsWith("video/")) {
      setPickError("Format video belum didukung. Pilih MP4/MOV/WebM.");
      return;
    }
    if (file.size > MAX_SOURCE) {
      setPickError(
        `Ukuran video ${formatFileSize(file.size)} melebihi batas ${formatFileSize(MAX_SOURCE)}. Rekam lebih pendek atau turunkan ke 1080p.`,
      );
      return;
    }
    try {
      const meta = await readVideoMetadata(file);
      if (meta.durationSec < MIN_DURATION) {
        setPickError(`Durasi terlalu pendek (${Math.round(meta.durationSec)} dtk). Minimal ${MIN_DURATION} detik.`);
        return;
      }
      setPicked({
        file,
        sizeLabel: formatFileSize(file.size),
        width: meta.width,
        height: meta.height,
        durationSec: meta.durationSec,
        qualityLabel: qualityLabel(meta.height),
      });
      setTrimStart(0);
      setTrimEnd(Math.min(meta.durationSec, MAX_DURATION));
    } catch {
      setPickError("Video tidak bisa dibaca. Coba pilih file lain.");
    }
  }

  async function onUpload() {
    if (!picked || uploading) return;
    setUploading(true);
    setProgress(0);
    let provisioned = false;
    try {
      // 1) Provision.
      const provRes = await fetch(`/api/admin/products/${productId}/video`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ videoDurationSec: Math.round(finalDuration) }),
      });
      const prov = (await provRes.json().catch(() => ({}))) as {
        videoGuid?: string;
        tus?: BunnyTusCredentials;
        error?: string;
      };
      if (!provRes.ok || !prov.tus) {
        throw new Error(prov.error ?? "Gagal menyiapkan upload.");
      }
      provisioned = true;

      // 2) Trim bila perlu.
      let blob: Blob = picked.file;
      const wantsTrim = trimStart > 0.1 || finalDuration < picked.durationSec - 0.1;
      if (wantsTrim) {
        setStage("trimming");
        setProgress(0);
        blob = await trimVideo(picked.file, {
          trimStartSec: trimStart,
          trimDurationSec: finalDuration,
          onProgress: setProgress,
        });
      }

      // 3) TUS upload.
      setStage("uploading");
      setProgress(0);
      await uploadToBunnyViaTus({
        file: blob,
        credentials: prov.tus,
        filetype: picked.file.type || "video/mp4",
        title: `product-${productId}`,
        onProgress: (pct) => setProgress(pct),
      });

      // 4) Mark processing.
      const patchRes = await fetch(`/api/admin/products/${productId}/video`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ videoDurationSec: Math.round(finalDuration) }),
      });
      if (!patchRes.ok) {
        throw new Error("Gagal menandai video sebagai diproses.");
      }

      setStatus("processing");
      setDurationSec(Math.round(finalDuration));
      setThumb(null);
      setPicked(null);
      show("Video diunggah — sedang diproses Bunny. Muncul di toko setelah selesai.");
    } catch (err) {
      if (provisioned) {
        setStatus(null);
        setThumb(null);
        setDurationSec(null);
      }
      show(err instanceof Error ? err.message : "Upload gagal. Coba lagi.");
    } finally {
      setUploading(false);
      setStage("");
      setProgress(0);
    }
  }

  async function onDelete() {
    setConfirmDelete(false);
    try {
      const res = await fetch(`/api/admin/products/${productId}/video`, {
        method: "DELETE",
      });
      if (!res.ok) throw new Error();
      setStatus(null);
      setThumb(null);
      setDurationSec(null);
      show("Video dihapus.");
    } catch {
      show("Gagal menghapus video.");
    }
  }

  const hasVideo =
    status === "ready" || status === "processing" || status === "failed" || status === "uploading";

  return (
    <div className="space-y-3">
      <input
        ref={inputRef}
        type="file"
        accept={ACCEPT}
        className="hidden"
        onChange={(e) => void onPick(e.target.files?.[0] ?? null)}
      />

      {/* State: sudah ada video (ready/processing/failed) & belum pilih file baru */}
      {hasVideo && !picked && (
        <div className="flex items-center gap-3 rounded-xl border border-zinc-200 p-3">
          <div className="relative h-20 w-20 shrink-0 overflow-hidden rounded-lg bg-zinc-100">
            {thumb ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={thumb} alt="Thumbnail video" className="h-full w-full object-cover" />
            ) : (
              <div className="grid h-full w-full place-items-center text-xs text-zinc-400">
                video
              </div>
            )}
          </div>
          <div className="min-w-0 flex-1">
            <StatusBadge status={status} />
            {durationSec ? (
              <p className="mt-1 text-xs text-zinc-500">{durationSec} detik</p>
            ) : null}
          </div>
          <div className="flex gap-2">
            <Button type="button" variant="secondary" size="sm" onClick={() => inputRef.current?.click()}>
              Ganti
            </Button>
            <DangerButton type="button" size="sm" onClick={() => setConfirmDelete(true)}>
              Hapus
            </DangerButton>
          </div>
        </div>
      )}

      {/* State: kosong & belum pilih */}
      {!hasVideo && !picked && (
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          className="flex w-full flex-col items-center gap-2 rounded-xl border border-dashed border-zinc-300 p-6 text-center transition hover:border-natalo-400 hover:bg-natalo-50/40"
        >
          <span className="text-sm font-semibold text-zinc-700">Tambah Video Produk</span>
          <span className="text-xs text-zinc-500">
            MP4/MOV · {MIN_DURATION}–{MAX_DURATION} detik · maks {formatFileSize(MAX_SOURCE)} · disarankan 1080p
          </span>
        </button>
      )}

      {/* State: file terpilih — kartu info otomatis + trim + upload */}
      {picked && (
        <div className="space-y-3 rounded-xl border border-zinc-200 p-3">
          <div className="flex flex-wrap items-center gap-2 text-xs">
            <span className="rounded-full bg-zinc-100 px-2 py-1 font-semibold text-zinc-700">
              {picked.sizeLabel}
            </span>
            <span className="rounded-full bg-zinc-100 px-2 py-1 font-semibold text-zinc-700">
              {picked.width}×{picked.height}
            </span>
            <span className="rounded-full bg-natalo-50 px-2 py-1 font-semibold text-natalo-700">
              {picked.qualityLabel}
            </span>
            <span className="rounded-full bg-zinc-100 px-2 py-1 font-semibold text-zinc-700">
              {Math.round(picked.durationSec)} dtk
            </span>
          </div>

          {picked.durationSec > MAX_DURATION && (
            <p className="text-xs font-semibold text-amber-600">
              Video lebih dari {MAX_DURATION} detik — atur rentang di bawah (maks {MAX_DURATION} dtk).
            </p>
          )}

          {/* Trim sederhana: dua range slider start/end */}
          <TrimRange
            durationSec={picked.durationSec}
            trimStart={trimStart}
            trimEnd={trimEnd}
            onStart={(v) =>
              setTrimStart(clamp(v, Math.max(0, trimEnd - MAX_DURATION), trimEnd - MIN_DURATION))
            }
            onEnd={(v) =>
              setTrimEnd(
                clamp(v, trimStart + MIN_DURATION, Math.min(picked.durationSec, trimStart + MAX_DURATION)),
              )
            }
          />
          <p className="text-xs text-zinc-500">
            Terpilih <span className="font-semibold text-zinc-800">{Math.round(finalDuration)} dtk</span>
          </p>

          {uploading && (
            <div className="space-y-1">
              <div className="h-2 overflow-hidden rounded-full bg-zinc-100">
                <div
                  className="h-full bg-natalo-600 transition-all"
                  style={{ width: `${progress}%` }}
                />
              </div>
              <p className="text-xs text-zinc-500">
                {stage === "trimming" ? "Memotong video…" : "Mengunggah…"} {progress}%
              </p>
            </div>
          )}

          <div className="flex gap-2">
            <Button
              type="button"
              onClick={() => void onUpload()}
              disabled={uploading || finalDuration < MIN_DURATION || finalDuration > MAX_DURATION}
            >
              {uploading ? "Memproses…" : "Unggah Video"}
            </Button>
            <Button type="button" variant="ghost" onClick={() => setPicked(null)} disabled={uploading}>
              Batal
            </Button>
          </div>
        </div>
      )}

      {pickError && (
        <p className="rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">
          {pickError}
        </p>
      )}

      <ConfirmDialog
        open={confirmDelete}
        title="Hapus video produk?"
        message="Video akan dihapus dari toko dan penyimpanan. Tindakan ini tidak bisa dibatalkan."
        confirmLabel="Hapus"
        variant="danger"
        onConfirm={() => void onDelete()}
        onCancel={() => setConfirmDelete(false)}
      />
    </div>
  );
}

function StatusBadge({ status }: { status: string | null }) {
  if (status === "ready")
    return <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-bold text-emerald-700">Tayang</span>;
  if (status === "processing")
    return <span className="rounded-full bg-amber-50 px-2 py-0.5 text-xs font-bold text-amber-700">Sedang diproses…</span>;
  if (status === "failed")
    return <span className="rounded-full bg-red-50 px-2 py-0.5 text-xs font-bold text-red-700">Gagal diproses</span>;
  if (status === "uploading")
    return (
      <span className="rounded-full bg-amber-50 px-2 py-0.5 text-xs font-bold text-amber-700">
        Menunggu unggahan…
      </span>
    );
  return null;
}

function TrimRange({
  durationSec,
  trimStart,
  trimEnd,
  onStart,
  onEnd,
}: {
  durationSec: number;
  trimStart: number;
  trimEnd: number;
  onStart: (v: number) => void;
  onEnd: (v: number) => void;
}) {
  return (
    <div className="space-y-2">
      <label className="block text-xs font-medium text-zinc-600">
        Mulai: {Math.round(trimStart)} dtk
        <input
          type="range"
          min={0}
          max={Math.ceil(durationSec)}
          step={1}
          value={trimStart}
          onChange={(e) => onStart(Number(e.target.value))}
          className="mt-1 w-full accent-natalo-600"
        />
      </label>
      <label className="block text-xs font-medium text-zinc-600">
        Selesai: {Math.round(trimEnd)} dtk
        <input
          type="range"
          min={0}
          max={Math.ceil(durationSec)}
          step={1}
          value={trimEnd}
          onChange={(e) => onEnd(Number(e.target.value))}
          className="mt-1 w-full accent-natalo-600"
        />
      </label>
    </div>
  );
}
