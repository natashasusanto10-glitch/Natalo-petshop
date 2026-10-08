"use client";

import {
  forwardRef,
  useEffect,
  useImperativeHandle,
  useRef,
  useState,
} from "react";
import { Button, DangerButton, useAdminToast } from "@/components/admin/ui";
import { readVideoMetadata } from "@/lib/feed/video-thumbnail";
import { formatFileSize } from "@/lib/feed/video-config";

import {
  isVideoFileReadable,
  uploadToBunnyViaTus,
  VIDEO_FILE_MISSING_MESSAGE,
  type BunnyTusCredentials,
} from "@/lib/feed/tus-upload";

import {
  isProductVideoType,
  prepareProductVideo,
  PRODUCT_VIDEO_MAX_BYTES as MAX_SOURCE,
  PRODUCT_VIDEO_MIN_SECONDS as MIN_DURATION,
  PRODUCT_VIDEO_MAX_SECONDS as MAX_DURATION,
} from "@/lib/product/product-video-prepare";

export type PreparedVideo = {
  file: File;
  durationSec: number;
  trimStartSec: number;
  trimEndSec: number;
};
export type ProductVideoDraftHandle = {
  openPicker(): void;
  prepareForSave(): Promise<PreparedVideo | null>;
  commitAfterProductSave(productId: string): Promise<void>;
  discardPendingCreation(): Promise<void>;
  getDraftState(): { hasPendingVideo: boolean; removeRequested: boolean };
};
type Initial = {
  videoGuid?: string | null;
  videoStatus: string | null;
  videoThumbnailUrl: string | null;
  videoDurationSec: number | null;
};

export const ProductVideoDraft = forwardRef<
  ProductVideoDraftHandle,
  {
    productId?: string;
    initial?: Initial;
    onDraftPreview?: (
      media: { url: string; durationSec: number } | null
    ) => void;
    onBusyChange?: (busy: boolean) => void;
    onIntentChange?: (intent: "keep" | "remove" | "replace") => void;
  }
>(function ProductVideoDraft(
  { productId, initial, onIntentChange, onBusyChange, onDraftPreview },
  ref
) {
  const { show } = useAdminToast();
  const inputRef = useRef<HTMLInputElement>(null);
  const preparedRef = useRef<PreparedVideo | null>(null);
  const pickVersion = useRef(0);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [progress, setProgress] = useState(0);
  const [phase, setPhase] = useState<"check" | "trim" | "compress" | "upload" | null>(null);
  const [picked, setPicked] = useState<PreparedVideo | null>(null);
  const [existingGuid, setExistingGuid] = useState(initial?.videoGuid ?? null);
  const [existingStatus, setExistingStatus] = useState(
    initial?.videoStatus ?? null
  );
  const [error, setError] = useState<string | null>(null);
  const [picking, setPicking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [removeRequested, setRemoveRequested] = useState(false);
  const [trimStartSec, setTrimStartSec] = useState(0);
  const [trimEndSec, setTrimEndSec] = useState(0);
  const [sourceDurationSec, setSourceDurationSec] = useState(0);

  useEffect(() => {
    onBusyChange?.(busy || picking);
  }, [busy, picking, onBusyChange]);
  const pickedFile = picked?.file;
  useEffect(() => {
    if (!pickedFile) {
      setPreviewUrl(null);
      return;
    }
    const url = URL.createObjectURL(pickedFile);
    setPreviewUrl(url);
    return () => URL.revokeObjectURL(url);
  }, [pickedFile]);

  const pickedDuration = picked?.durationSec;
  useEffect(() => {
    onDraftPreview?.(
      previewUrl && pickedDuration
        ? { url: previewUrl, durationSec: pickedDuration }
        : null
    );
  }, [previewUrl, pickedDuration, onDraftPreview]);

  async function pick(file: File | null) {
    setError(null);
    setPicking(false);
    const version = ++pickVersion.current;
    if (!file) return;
    if (!isProductVideoType(file))
      return setError("Format video belum didukung. Pilih MP4/MOV/WebM.");
    if (file.size > MAX_SOURCE)
      return setError(`Ukuran video melebihi ${formatFileSize(MAX_SOURCE)}.`);
    setPicking(true);
    try {
      const meta = await readVideoMetadata(file);
      if (version !== pickVersion.current) return;
      if (!Number.isFinite(meta.durationSec))
        return setError("Durasi video tidak valid.");
      if (meta.durationSec < MIN_DURATION)
        return setError(`Durasi minimal ${MIN_DURATION} detik.`);
      const end = Math.min(meta.durationSec, MAX_DURATION);
      preparedRef.current = null;
      setRemoveRequested(false);
      onIntentChange?.("replace");
      setSourceDurationSec(meta.durationSec);
      setTrimStartSec(0);
      setTrimEndSec(end);
      setPicked({
        file,
        durationSec: Math.round(end),
        trimStartSec: 0,
        trimEndSec: end,
      });
    } catch {
      if (version === pickVersion.current)
        setError("Video tidak bisa dibaca. Coba pilih file lain.");
    } finally {
      if (version === pickVersion.current) setPicking(false);
    }
  }

  useImperativeHandle(
    ref,
    () => ({
      openPicker() {
        inputRef.current?.click();
      },
      async prepareForSave() {
        if (!picked) return null;
        if (preparedRef.current) return preparedRef.current;
        if (!(await isVideoFileReadable(picked.file))) {
          setError(VIDEO_FILE_MISSING_MESSAGE);
          throw new Error(VIDEO_FILE_MISSING_MESSAGE);
        }
        setBusy(true);
        setPhase("check");
        setError(null);
        setProgress(0);
        try {
          const result = await prepareProductVideo(picked.file, {
            trimStartSec: picked.trimStartSec,
            trimEndSec: picked.trimEndSec,
            onPhase: setPhase,
            onProgress: setProgress,
          });
          const prepared = {
            file: result.file,
            durationSec: result.durationSec,
            trimStartSec: 0,
            trimEndSec: result.durationSec,
          };
          preparedRef.current = prepared;
          return prepared;
        } catch (err) {
          setError(
            err instanceof Error ? err.message : "Persiapan video gagal."
          );
          throw err;
        } finally {
          setBusy(false);
          setPhase(null);
        }
      },
      async commitAfterProductSave(id: string) {
        if (!picked) return;
        if (!preparedRef.current)
          throw new Error(
            "Video belum siap diunggah. Coba simpan kembali."
          );
        const prepared = preparedRef.current;
        setBusy(true);
        setPhase("upload");
        setProgress(0);
        let createdGuid: string | null = null;
        try {
          const provision = await fetch(`/api/admin/products/${id}/video`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ videoDurationSec: prepared.durationSec }),
          });
          const data = (await provision.json().catch(() => ({}))) as {
            videoGuid?: string;
            tus?: BunnyTusCredentials;
            error?: string;
          };
          if (!provision.ok || !data.videoGuid || !data.tus)
            throw new Error(data.error ?? "Gagal menyiapkan upload.");
          createdGuid = data.videoGuid;
          await uploadToBunnyViaTus({
            file: prepared.file,
            credentials: data.tus,
            filetype: prepared.file.type,
            title: `product-${id}`,
            onProgress: (percent) => setProgress(percent),
          });
          const done = await fetch(`/api/admin/products/${id}/video`, {
            method: "PATCH",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              videoGuid: createdGuid,
              videoDurationSec: prepared.durationSec,
            }),
          });
          if (!done.ok)
            throw new Error("Gagal menandai video sebagai diproses.");
          setExistingGuid(createdGuid);
          setExistingStatus("processing");
          setPicked(null);
          show("Video diunggah dan sedang diproses.");
        } catch (err) {
          setError(err instanceof Error ? err.message : "Upload video gagal.");
          if (id && createdGuid)
            await fetch(`/api/admin/products/${id}/video`, {
              method: "DELETE",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ videoGuid: createdGuid }),
            }).catch(() => undefined);
          throw err;
        } finally {
          setBusy(false);
          setPhase(null);
        }
      },
      async discardPendingCreation() {
        preparedRef.current = null;
        setPicked(null);
      },
      getDraftState() {
        return { hasPendingVideo: Boolean(picked), removeRequested };
      },
    }),
    [picked, show, removeRequested]
  );

  async function remove() {
    // Draft intent only: the parent decides whether deletion is committed.
    ++pickVersion.current;
    setPicking(false);
    preparedRef.current = null;
    setRemoveRequested(true);
    setExistingGuid(null);
    setExistingStatus(null);
    setPicked(null);
    onIntentChange?.("remove");
  }

  return (
    <div className="mt-5">
      <input
        ref={inputRef}
        type="file"
        accept="video/mp4,video/quicktime,video/webm,video/*"
        className="hidden"
        onChange={(event) => {
          void pick(event.target.files?.[0] ?? null);
          event.currentTarget.value = "";
        }}
      />
      <div className="admin-video-row">
        <button
          type="button"
          className="admin-video-tile"
          disabled={busy || picking}
          aria-label={
            picked || existingGuid
              ? "Ganti video produk"
              : "Tambah video produk"
          }
          onClick={() => inputRef.current?.click()}
        >
          {previewUrl ? (
            <video src={previewUrl} muted playsInline preload="metadata" />
          ) : existingGuid && initial?.videoThumbnailUrl ? (
            <img src={initial.videoThumbnailUrl} alt="Video produk" />
          ) : (
            <>
              <svg
                width="22"
                height="22"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
              >
                <rect x="3" y="4" width="18" height="14" rx="2" />
                <path d="m10 8 5 3-5 3ZM12 18v4M9 21h6" />
              </svg>
              <span>Tambah video</span>
            </>
          )}
          {(picked?.durationSec || initial?.videoDurationSec) && (
            <span className="admin-video-duration">
              {picked?.durationSec ?? initial?.videoDurationSec} dtk
            </span>
          )}
        </button>
        <div className="min-w-0 flex-1 text-xs text-slate-500">
          <p className="mb-1 font-semibold text-slate-700">Video produk</p>
          <p>
            {picked
              ? `${picked.file.name} · ${formatFileSize(picked.file.size)}`
              : existingGuid
              ? `Video ${
                  existingStatus === "ready"
                    ? "siap"
                    : existingStatus === "processing"
                    ? "sedang diproses"
                    : existingStatus ?? "tersedia"
                }`
              : "MP4, MOV, atau WebM · 10–60 detik"}
          </p>
          <p className="mt-1">Maks. 200 MB · Video utuh yang sesuai langsung diunggah saat produk disimpan, lalu diproses untuk pemutaran.</p>
          {(picked || existingGuid) && (
            <div className="mt-2 flex flex-wrap gap-2">
              <Button
                type="button"
                size="sm"
                variant="secondary"
                disabled={busy || picking}
                onClick={() => inputRef.current?.click()}
              >
                Ganti
              </Button>
              <DangerButton
                type="button"
                size="sm"
                disabled={busy || picking}
                onClick={() => void remove()}
              >
                Hapus
              </DangerButton>
            </div>
          )}
        </div>
      </div>
      {picked && (
        <details className="mt-3 rounded-lg border border-slate-200 p-3 text-xs">
          <summary className="cursor-pointer py-2 font-semibold">
            Potong video · {picked.durationSec} detik
          </summary>
          <label className="mt-3 block">
            Mulai {trimStartSec} dtk
            <input
              disabled={busy || picking}
              type="range"
              min={0}
              max={Math.max(0, trimEndSec - MIN_DURATION)}
              value={trimStartSec}
              onChange={(event) => {
                const v = Number(event.target.value);
                preparedRef.current = null;
                setTrimStartSec(v);
                setPicked({
                  ...picked,
                  trimStartSec: v,
                  durationSec: Math.round(trimEndSec - v),
                });
              }}
              className="mt-2 w-full"
            />
          </label>
          <label className="mt-2 block">
            Selesai {trimEndSec} dtk
            <input
              disabled={busy || picking}
              type="range"
              min={trimStartSec + MIN_DURATION}
              max={Math.min(sourceDurationSec, trimStartSec + MAX_DURATION)}
              value={trimEndSec}
              onChange={(event) => {
                const v = Number(event.target.value);
                preparedRef.current = null;
                setTrimEndSec(v);
                setPicked({
                  ...picked,
                  trimEndSec: v,
                  durationSec: Math.round(v - trimStartSec),
                });
              }}
              className="mt-2 w-full"
            />
          </label>
        </details>
      )}
      {busy && (
        <div className="mt-3 text-xs text-blue-700" role="status">
          <p>
            {phase === "check" ? "Memeriksa video…" : `${phase === "trim" ? "Memotong video" : phase === "compress" ? "Menyesuaikan potongan video" : "Mengunggah video"} · ${Math.round(progress)}%`}
          </p>
          <progress
            aria-label={
              phase === "check" ? "Pemeriksaan video" : phase === "trim" ? "Pemotongan video" : phase === "compress" ? "Penyesuaian video" : "Unggah video"
            }
            value={phase === "check" ? undefined : progress}
            max={100}
            className="mt-2 h-1 w-full"
          />
        </div>
      )}
      {error && (
        <p
          role="alert"
          className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700"
        >
          {error}
        </p>
      )}
    </div>
  );
});
export default ProductVideoDraft;
