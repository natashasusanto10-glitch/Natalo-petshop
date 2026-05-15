"use client";

/**
 * Upload form untuk user community video. Spec section 6 flow:
 *   1. User buka feed
 *   2. Tap tombol upload / plus
 *   3. Pilih video
 *   4. Isi judul
 *   5. Isi deskripsi
 *   6. (Pilih kategori) — skip di MVP per keputusan user
 *   7. (Pilih produk yang dipakai, opsional) — di-implement
 *   8. Preview video
 *   9. Upload
 *  10. Tampilkan success screen dengan Lottie
 *
 * Field user TIDAK boleh: harga, stok, promo, tombol beli, link jualan
 * (di-enforce server-side juga — POST /api/feed/posts override kind=COMMUNITY).
 *
 * Spec 10.5: hard size limit 30 MB (lihat /api/feed/upload-video).
 *
 * Flow internal:
 *   A. User pilih file → readVideoMetadata + extract thumbnail di client
 *   B. User isi judul/deskripsi/produk
 *   C. Tap "Upload" → upload video → upload thumbnail → create post → success
 *   D. Success screen dengan Lottie + tombol "Kembali ke Feed"
 */
import { useRouter } from "next/navigation";
import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { FiArrowLeft, FiCheck, FiPackage, FiPause, FiPlay, FiUploadCloud, FiVideo, FiX } from "react-icons/fi";
import { BottomSheet } from "@/components/BottomSheet";
import { formatRupiah } from "@/lib/format";
import { hapticSuccess, hapticTap, hapticWarning } from "@/lib/native/haptics";
import {
  extractVideoThumbnailSafe,
  readVideoMetadata,
  type VideoMetadata,
} from "@/lib/feed/video-thumbnail";
import {
  formatFileSize,
  MAX_SOURCE_VIDEO_SIZE,
  USER_VIDEO_CONFIG,
} from "@/lib/feed/video-config";
import { FeedUploadSuccessLottie } from "./FeedUploadSuccessLottie";

const MAX_TITLE_LENGTH = 200;
const MAX_DESC_LENGTH = 300;
const ACCEPT_VIDEO = "video/mp4,video/quicktime";

type Step = "pick" | "trim" | "form" | "uploading" | "success" | "error";

// Allow longer source videos so users can trim down. Server-side validator
// at /api/feed/posts still enforces 1-45s on the FINAL trimmed clip.
const SOURCE_MAX_SECONDS = 180;
type ProcessingStage =
  | "validating"
  | "compressing"
  | "generating-thumbnail"
  | "uploading"
  | "submitting"
  | null;

type PinnableProduct = {
  productId: string;
  slug: string;
  name: string;
  imageUrl: string | null;
  price: number;
  originalPrice: number;
  stock: number;
  avgRating: number;
  reviewCount: number;
  purchasedAt: string;
  orderNumber: string;
};

export function FeedUploadClient() {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [step, setStep] = useState<Step>("pick");
  const [file, setFile] = useState<File | null>(null);
  const [filePreviewUrl, setFilePreviewUrl] = useState<string | null>(null);
  const [metadata, setMetadata] = useState<VideoMetadata | null>(null);
  const [thumbnailBlob, setThumbnailBlob] = useState<Blob | null>(null);
  const [thumbnailPreviewUrl, setThumbnailPreviewUrl] = useState<string | null>(null);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [analyzing, setAnalyzing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploadProgress, setUploadProgress] = useState<string>("");
  const [processingStage, setProcessingStage] = useState<ProcessingStage>(null);
  const [processingProgress, setProcessingProgress] = useState(0);
  const [pinnableProducts, setPinnableProducts] = useState<PinnableProduct[]>([]);
  const [productsLoading, setProductsLoading] = useState(false);
  const [productPickerOpen, setProductPickerOpen] = useState(false);
  const [selectedProduct, setSelectedProduct] = useState<PinnableProduct | null>(null);
  // Trim state — defaults set when video is picked. trimEnd defaults to
  // min(sourceDuration, MAX_DURATION) so a short video just opens already-valid.
  const [trimStart, setTrimStart] = useState(0);
  const [trimEnd, setTrimEnd] = useState(USER_VIDEO_CONFIG.maxDuration);
  const [trimPreviewPlaying, setTrimPreviewPlaying] = useState(false);
  const trimVideoRef = useRef<HTMLVideoElement>(null);

  const finalDuration = Math.max(0, trimEnd - trimStart);
  const trimValid =
    finalDuration >= USER_VIDEO_CONFIG.minDuration &&
    finalDuration <= USER_VIDEO_CONFIG.maxDuration;

  useEffect(() => {
    return () => {
      if (filePreviewUrl) URL.revokeObjectURL(filePreviewUrl);
    };
  }, [filePreviewUrl]);
  useEffect(() => {
    return () => {
      if (thumbnailPreviewUrl) URL.revokeObjectURL(thumbnailPreviewUrl);
    };
  }, [thumbnailPreviewUrl]);

  useEffect(() => {
    let cancelled = false;
    setProductsLoading(true);
    fetch("/api/feed/pinnable-products")
      .then((res) => {
        if (!res.ok) return { products: [] };
        return res.json() as Promise<{ products: PinnableProduct[] }>;
      })
      .then((data) => {
        if (!cancelled) setPinnableProducts(data.products ?? []);
      })
      .catch(() => {
        if (!cancelled) setPinnableProducts([]);
      })
      .finally(() => {
        if (!cancelled) setProductsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  function resetSelection() {
    if (filePreviewUrl) URL.revokeObjectURL(filePreviewUrl);
    if (thumbnailPreviewUrl) URL.revokeObjectURL(thumbnailPreviewUrl);
    setFile(null);
    setFilePreviewUrl(null);
    setMetadata(null);
    setThumbnailBlob(null);
    setThumbnailPreviewUrl(null);
    setError(null);
  }

  async function handleFilePick(picked: File | null) {
    if (!picked) return;
    resetSelection();
    setError(null);

    // Client-side validation — mirror server validation di route.
    if (!picked.type.startsWith("video/")) {
      setError("File harus berupa video.");
      hapticWarning();
      return;
    }
    if (picked.size > MAX_SOURCE_VIDEO_SIZE) {
      setError(`Ukuran video mentah maksimal ${formatFileSize(MAX_SOURCE_VIDEO_SIZE)}.`);
      hapticWarning();
      return;
    }

    const pickedPreviewUrl = URL.createObjectURL(picked);
    setFile(picked);
    setFilePreviewUrl(pickedPreviewUrl);
    setAnalyzing(true);
    setProcessingStage("validating");
    setProcessingProgress(0);

    try {
      const meta = await readVideoMetadata(picked);
      setMetadata(meta);
      if (meta.durationSec < USER_VIDEO_CONFIG.minDuration) {
        URL.revokeObjectURL(pickedPreviewUrl);
        resetSelection();
        setError(`Video terlalu pendek. Minimal ${USER_VIDEO_CONFIG.minDuration} detik.`);
        hapticWarning();
        setAnalyzing(false);
        return;
      }
      if (meta.durationSec > SOURCE_MAX_SECONDS) {
        URL.revokeObjectURL(pickedPreviewUrl);
        resetSelection();
        setError(
          `Video terlalu panjang (${Math.round(meta.durationSec)}s). Maksimal ${SOURCE_MAX_SECONDS} detik untuk source.`,
        );
        hapticWarning();
        setAnalyzing(false);
        return;
      }
      // Seed trim range — start at 0, end at min(duration, max-allowed).
      // User opens the trim screen with a valid selection already.
      setTrimStart(0);
      setTrimEnd(Math.min(meta.durationSec, USER_VIDEO_CONFIG.maxDuration));

      setProcessingStage("generating-thumbnail");
      const thumb = await extractVideoThumbnailSafe(picked, meta, {
        targetTimeSec: Math.min(1, meta.durationSec / 2),
        maxWidth: 480,
        timeoutMs: 30000,
        onError: (thumbnailError) => {
          console.info("[feed-video] legacy-thumbnail:fallback", {
            fileName: picked.name,
            size: picked.size,
            mimeType: picked.type,
            durationSec: meta.durationSec,
            error:
              thumbnailError instanceof Error
                ? {
                    name: thumbnailError.name,
                    message: thumbnailError.message,
                    stack: thumbnailError.stack,
                  }
                : { message: String(thumbnailError) },
            usedFallback: true,
          });
        },
      });
      setThumbnailBlob(thumb.blob);
      setThumbnailPreviewUrl(URL.createObjectURL(thumb.blob));
      // Always show the trim screen — even a short video benefits from a
      // confirmation step. Avoids the "where's trim?" complaint.
      setStep("trim");
      hapticTap();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal proses video.");
      hapticWarning();
    } finally {
      setAnalyzing(false);
      setProcessingStage(null);
    }
  }

  async function handleUpload() {
    if (!file || !metadata || !thumbnailBlob) return;
    if (title.trim().length < 3) {
      setError("Judul minimal 3 karakter.");
      return;
    }
    setStep("uploading");
    setError(null);

    try {
      setProcessingStage("compressing");
      setProcessingProgress(0);
      setUploadProgress("Memproses video...");
      const { compressVideo } = await import("@/lib/feed/video-compressor");
      const compressedFile = await compressVideo(file, {
        config: USER_VIDEO_CONFIG,
        // Trim values picked in the "trim" step — pass through so ffmpeg
        // only encodes the selected slice and the final clip lands in
        // the 1-45s server-side window.
        trimStartSec: trimStart,
        trimDurationSec: finalDuration,
        onProgress: (progress) => {
          setProcessingProgress(progress);
        },
      });
      if (compressedFile.size > USER_VIDEO_CONFIG.maxFileSize) {
        throw new Error(
          `Hasil kompresi masih ${formatFileSize(compressedFile.size)}. Maksimal ${formatFileSize(USER_VIDEO_CONFIG.maxFileSize)}.`,
        );
      }

      // 1. Upload video terkompresi
      setProcessingStage("uploading");
      setProcessingProgress(0);
      setUploadProgress("Mengunggah video...");
      const videoForm = new FormData();
      videoForm.append("file", compressedFile);
      const videoRes = await fetch("/api/feed/upload-video", {
        method: "POST",
        body: videoForm,
      });
      const videoData = await videoRes.json();
      if (!videoRes.ok) throw new Error(videoData.error ?? "Upload video gagal.");

      // 2. Upload thumbnail
      setUploadProgress("Mengunggah thumbnail...");
      const thumbForm = new FormData();
      thumbForm.append(
        "file",
        new File([thumbnailBlob], "thumbnail.jpg", { type: "image/jpeg" }),
      );
      const thumbRes = await fetch("/api/feed/upload-thumbnail", {
        method: "POST",
        body: thumbForm,
      });
      const thumbData = await thumbRes.json();
      if (!thumbRes.ok) throw new Error(thumbData.error ?? "Upload thumbnail gagal.");

      // 3. Create post — server set kind=COMMUNITY, status=PENDING_REVIEW.
      setProcessingStage("submitting");
      setUploadProgress("Menyimpan...");
      const postRes = await fetch("/api/feed/posts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: title.trim(),
          description: description.trim() || null,
          videoUrl: videoData.url,
          thumbnailUrl: thumbData.url,
          videoMimeType: videoData.mimeType,
          videoSizeBytes: videoData.sizeBytes,
          // Final clip duration after trim, not source duration. Server
          // validates this against 1-45s and would reject a 60s source.
          videoDurationSec: Math.max(1, Math.round(finalDuration)),
          videoWidth: metadata.width,
          videoHeight: metadata.height,
          productId: selectedProduct?.productId ?? null,
        }),
      });
      const postData = await postRes.json();
      if (!postRes.ok) throw new Error(postData.error ?? "Gagal membuat post.");

      hapticSuccess();
      setStep("success");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload gagal. Coba lagi.");
      setStep("form");
      hapticWarning();
    } finally {
      setProcessingStage(null);
      setProcessingProgress(0);
    }
  }

  // ── Render per step ───────────────────────────────────────────────
  if (step === "success") {
    return (
      <div className="flex min-h-[100dvh] flex-col items-center justify-center px-6 pb-24 pt-16 text-center">
        <FeedUploadSuccessLottie />
        <h1 className="mt-4 text-xl font-black text-natalo-700">
          Video Berhasil Diupload!
        </h1>
        <p className="mt-3 max-w-sm text-sm leading-relaxed text-gray-600">
          Terima kasih sudah berbagi pengalaman bersama komunitas Natalo.
          Tim kami akan review videomu sebelum tampil di tab Komunitas.
        </p>
        <div className="mt-8 flex w-full max-w-xs flex-col gap-2">
          <button
            type="button"
            onClick={() => router.push("/feed")}
            className="rounded-full bg-natalo-600 py-3 text-sm font-extrabold text-white shadow-sm transition active:scale-95"
          >
            Kembali ke Feed
          </button>
          <button
            type="button"
            onClick={() => {
              resetSelection();
              setTitle("");
              setDescription("");
              setSelectedProduct(null);
              setStep("pick");
            }}
            className="rounded-full border border-natalo-200 py-3 text-sm font-extrabold text-natalo-700 transition active:bg-natalo-50"
          >
            Upload Lagi
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl px-4 pb-32 pt-4">
      {/* Header */}
      <header className="mb-6 flex items-center gap-3">
        <button
          type="button"
          onClick={() => router.back()}
          aria-label="Kembali"
          className="grid h-10 w-10 place-items-center rounded-full bg-white shadow-sm"
        >
          <FiArrowLeft className="h-5 w-5 text-gray-700" />
        </button>
        <div>
          <h1 className="text-base font-black text-gray-900">Upload Video Komunitas</h1>
          <p className="text-[11px] font-semibold text-gray-500">
            Bagikan pengalaman bersama hewan peliharaanmu
          </p>
        </div>
      </header>

      {step === "pick" || !file ? (
        <PickPanel
          onPick={(f) => handleFilePick(f)}
          analyzing={analyzing}
          error={error}
          fileInputRef={fileInputRef}
        />
      ) : step === "trim" && metadata && filePreviewUrl ? (
        <TrimPanel
          videoSrc={filePreviewUrl}
          videoRef={trimVideoRef}
          durationSec={metadata.durationSec}
          trimStart={trimStart}
          trimEnd={trimEnd}
          finalDuration={finalDuration}
          isValid={trimValid}
          isPlaying={trimPreviewPlaying}
          onTrimStartChange={(v) => {
            const next = Math.max(0, Math.min(v, trimEnd - 0.5));
            setTrimStart(next);
            const video = trimVideoRef.current;
            if (video) video.currentTime = next;
          }}
          onTrimEndChange={(v) => {
            const next = Math.max(trimStart + 0.5, Math.min(v, metadata.durationSec));
            setTrimEnd(next);
          }}
          onTogglePlay={() => {
            const video = trimVideoRef.current;
            if (!video) return;
            if (video.paused) {
              if (video.currentTime < trimStart || video.currentTime >= trimEnd) {
                video.currentTime = trimStart;
              }
              video.play().then(() => setTrimPreviewPlaying(true)).catch(() => {});
            } else {
              video.pause();
              setTrimPreviewPlaying(false);
            }
          }}
          onPause={() => setTrimPreviewPlaying(false)}
          onTimeUpdate={() => {
            const video = trimVideoRef.current;
            if (!video) return;
            if (video.currentTime >= trimEnd) {
              video.pause();
              video.currentTime = trimStart;
              setTrimPreviewPlaying(false);
            }
          }}
          onBack={() => {
            const video = trimVideoRef.current;
            if (video) video.pause();
            setTrimPreviewPlaying(false);
            resetSelection();
            setStep("pick");
          }}
          onNext={() => {
            const video = trimVideoRef.current;
            if (video) video.pause();
            setTrimPreviewPlaying(false);
            setStep("form");
            hapticTap();
          }}
        />
      ) : (
        <FormPanel
          file={file}
          metadata={metadata}
          thumbnailPreviewUrl={thumbnailPreviewUrl}
          title={title}
          description={description}
          selectedProduct={selectedProduct}
          pinnableProducts={pinnableProducts}
          productsLoading={productsLoading}
          productPickerOpen={productPickerOpen}
          onTitleChange={setTitle}
          onDescriptionChange={setDescription}
          onOpenProductPicker={() => setProductPickerOpen(true)}
          onCloseProductPicker={() => setProductPickerOpen(false)}
          onSelectProduct={(product) => {
            setSelectedProduct(product);
            setProductPickerOpen(false);
          }}
          onClearProduct={() => setSelectedProduct(null)}
          onChangeFile={() => {
            resetSelection();
            setStep("pick");
          }}
          onSubmit={handleUpload}
          uploading={step === "uploading"}
          uploadProgress={uploadProgress}
          processingStage={processingStage}
          processingProgress={processingProgress}
          error={error}
        />
      )}
    </div>
  );
}

// ── Sub-panels ────────────────────────────────────────────────────────

function PickPanel({
  onPick,
  analyzing,
  error,
  fileInputRef,
}: {
  onPick: (f: File | null) => void;
  analyzing: boolean;
  error: string | null;
  fileInputRef: React.RefObject<HTMLInputElement | null>;
}) {
  return (
    <div className="rounded-3xl border border-dashed border-gray-200 bg-white p-8 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-natalo-50">
        <FiVideo className="h-8 w-8 text-natalo-600" />
      </div>
      <h2 className="mt-4 text-sm font-extrabold text-gray-900">Pilih video</h2>
      <p className="mt-2 text-xs text-gray-500">
        MP4 atau MOV · video mentah max {formatFileSize(MAX_SOURCE_VIDEO_SIZE)} · durasi{" "}
        {USER_VIDEO_CONFIG.minDuration}-{USER_VIDEO_CONFIG.maxDuration} detik
      </p>

      <input
        ref={fileInputRef}
        type="file"
        accept={ACCEPT_VIDEO}
        className="hidden"
        onChange={(e) => onPick(e.target.files?.[0] ?? null)}
      />
      <button
        type="button"
        onClick={() => fileInputRef.current?.click()}
        disabled={analyzing}
        className="mt-5 inline-flex items-center gap-2 rounded-full bg-natalo-600 px-6 py-3 text-sm font-extrabold text-white transition active:scale-95 disabled:opacity-50"
      >
        <FiUploadCloud className="h-4 w-4" />
        {analyzing ? "Memproses..." : "Pilih video"}
      </button>

      {error && (
        <p className="mt-4 rounded-2xl bg-red-50 p-3 text-xs font-bold text-red-700">
          {error}
        </p>
      )}
    </div>
  );
}

function TrimPanel({
  videoSrc,
  videoRef,
  durationSec,
  trimStart,
  trimEnd,
  finalDuration,
  isValid,
  isPlaying,
  onTrimStartChange,
  onTrimEndChange,
  onTogglePlay,
  onPause,
  onTimeUpdate,
  onBack,
  onNext,
}: {
  videoSrc: string;
  videoRef: React.RefObject<HTMLVideoElement | null>;
  durationSec: number;
  trimStart: number;
  trimEnd: number;
  finalDuration: number;
  isValid: boolean;
  isPlaying: boolean;
  onTrimStartChange: (v: number) => void;
  onTrimEndChange: (v: number) => void;
  onTogglePlay: () => void;
  onPause: () => void;
  onTimeUpdate: () => void;
  onBack: () => void;
  onNext: () => void;
}) {
  const invalidText =
    finalDuration < USER_VIDEO_CONFIG.minDuration
      ? `Video terlalu pendek. Minimal ${USER_VIDEO_CONFIG.minDuration} detik.`
      : `Video terlalu panjang. Maksimal ${USER_VIDEO_CONFIG.maxDuration} detik.`;

  return (
    <main className="flex min-h-[100dvh] flex-col bg-black text-white">
      <header className="flex shrink-0 items-center justify-between gap-3 border-b border-white/10 px-4 py-3 pt-[calc(env(safe-area-inset-top)+12px)]">
        <button
          type="button"
          onClick={onBack}
          aria-label="Kembali"
          className="flex h-10 w-10 items-center justify-center rounded-full text-white/85 transition active:bg-white/10"
        >
          <FiArrowLeft className="h-5 w-5" />
        </button>
        <h1 className="text-base font-black">Trim Video</h1>
        <button
          type="button"
          onClick={onNext}
          disabled={!isValid}
          className="rounded-full bg-natalo-600 px-5 py-2 text-sm font-black text-white transition active:scale-[0.98] disabled:cursor-not-allowed disabled:bg-zinc-700 disabled:text-zinc-400"
        >
          Lanjut
        </button>
      </header>

      <div className="flex-1 overflow-y-auto px-4 pb-[calc(24px+env(safe-area-inset-bottom))]">
        <div className="mx-auto max-w-2xl pt-4">
          <div className="relative overflow-hidden rounded-[28px] bg-white/10">
            <video
              ref={videoRef}
              src={videoSrc}
              className="aspect-[9/14] w-full object-cover"
              playsInline
              muted
              onPause={onPause}
              onTimeUpdate={onTimeUpdate}
              onEnded={() => {
                const video = videoRef.current;
                if (video) video.currentTime = trimStart;
                onPause();
              }}
            />
            <button
              type="button"
              onClick={onTogglePlay}
              aria-label={isPlaying ? "Pause video" : "Play video"}
              className="absolute bottom-4 left-4 grid h-12 w-12 place-items-center rounded-full bg-black/55 text-white backdrop-blur"
            >
              {isPlaying ? <FiPause className="h-5 w-5" /> : <FiPlay className="h-5 w-5" />}
            </button>
            <span className="absolute bottom-5 left-1/2 -translate-x-1/2 rounded-full bg-black/55 px-3 py-1.5 text-sm font-black">
              {formatTrimDuration(finalDuration)} / {formatTrimDuration(durationSec)}
            </span>
          </div>

          <div className="mt-5 rounded-3xl border border-white/10 bg-white/10 p-4">
            <div className="mb-3 flex items-center justify-between text-xs font-black text-white/65">
              <span>{formatTrimDuration(trimStart)}</span>
              <span>{formatTrimDuration(trimEnd)}</span>
            </div>
            <div className="rounded-2xl border border-natalo-400/70 bg-black/50 p-3">
              <div className="h-14 overflow-hidden rounded-xl bg-[linear-gradient(90deg,rgba(30,95,191,.55),rgba(255,255,255,.14),rgba(30,95,191,.55))]" />
              <label className="mt-4 block text-xs font-black text-white/60">
                Mulai trim
                <input
                  type="range"
                  min={0}
                  max={Math.max(0, durationSec - 0.5)}
                  step={0.1}
                  value={trimStart}
                  onChange={(event) => onTrimStartChange(Number(event.target.value))}
                  className="mt-2 w-full accent-natalo-500"
                />
              </label>
              <label className="mt-3 block text-xs font-black text-white/60">
                Akhir trim
                <input
                  type="range"
                  min={Math.min(durationSec, trimStart + 0.5)}
                  max={durationSec}
                  step={0.1}
                  value={trimEnd}
                  onChange={(event) => onTrimEndChange(Number(event.target.value))}
                  className="mt-2 w-full accent-natalo-500"
                />
              </label>
            </div>
          </div>

          <div
            className={`mt-3 rounded-3xl px-4 py-3 text-sm font-black ${
              isValid
                ? "bg-natalo-600/25 text-natalo-50 ring-1 ring-natalo-400/30"
                : "bg-amber-500/15 text-amber-200 ring-1 ring-amber-400/40"
            }`}
          >
            {isValid
              ? `Durasi final ${formatTrimDuration(finalDuration)} — sudah valid`
              : invalidText}
          </div>
        </div>
      </div>
    </main>
  );
}

function formatTrimDuration(sec: number) {
  const total = Math.max(0, Math.round(sec));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function FormPanel({
  file,
  metadata,
  thumbnailPreviewUrl,
  title,
  description,
  selectedProduct,
  pinnableProducts,
  productsLoading,
  productPickerOpen,
  onTitleChange,
  onDescriptionChange,
  onOpenProductPicker,
  onCloseProductPicker,
  onSelectProduct,
  onClearProduct,
  onChangeFile,
  onSubmit,
  uploading,
  uploadProgress,
  processingStage,
  processingProgress,
  error,
}: {
  file: File;
  metadata: VideoMetadata | null;
  thumbnailPreviewUrl: string | null;
  title: string;
  description: string;
  selectedProduct: PinnableProduct | null;
  pinnableProducts: PinnableProduct[];
  productsLoading: boolean;
  productPickerOpen: boolean;
  onTitleChange: (v: string) => void;
  onDescriptionChange: (v: string) => void;
  onOpenProductPicker: () => void;
  onCloseProductPicker: () => void;
  onSelectProduct: (product: PinnableProduct) => void;
  onClearProduct: () => void;
  onChangeFile: () => void;
  onSubmit: () => void;
  uploading: boolean;
  uploadProgress: string;
  processingStage: ProcessingStage;
  processingProgress: number;
  error: string | null;
}) {
  const dur = metadata?.durationSec ?? 0;
  const w = metadata?.width ?? 0;
  const h = metadata?.height ?? 0;

  return (
    <div className="space-y-4">
      {/* Preview thumbnail */}
      <div className="overflow-hidden rounded-3xl border border-gray-100 bg-white">
        <div className="relative aspect-[9/16] w-full bg-gray-100">
          {thumbnailPreviewUrl ? (
            <Image
              src={thumbnailPreviewUrl}
              alt="Preview thumbnail"
              fill
              sizes="(max-width: 768px) 100vw, 480px"
              className="object-cover"
              unoptimized
            />
          ) : null}
          <button
            type="button"
            onClick={onChangeFile}
            aria-label="Ganti video"
            disabled={uploading}
            className="absolute right-3 top-3 grid h-9 w-9 place-items-center rounded-full bg-black/60 text-white backdrop-blur-sm transition active:scale-95 disabled:opacity-50"
          >
            <FiX className="h-4 w-4" />
          </button>
        </div>
        <div className="space-y-1 px-4 py-3 text-[11px] font-semibold text-gray-500">
          <p>
            <span className="font-extrabold text-gray-700">{file.name}</span>
            <span> · {(file.size / 1024 / 1024).toFixed(1)} MB</span>
          </p>
          {dur > 0 && (
            <p>
              Durasi {Math.round(dur)}s · Resolusi {w}×{h}
            </p>
          )}
        </div>
      </div>

      {/* Title + description */}
      <div className="space-y-3 rounded-3xl border border-gray-100 bg-white p-4">
        <div>
          <label
            htmlFor="feed-title"
            className="text-xs font-extrabold text-gray-700"
          >
            Judul <span className="text-red-500">*</span>
          </label>
          <input
            id="feed-title"
            type="text"
            value={title}
            onChange={(e) => onTitleChange(e.target.value)}
            disabled={uploading}
            maxLength={MAX_TITLE_LENGTH}
            placeholder="Contoh: Kucing aku suka banget Royal Canin!"
            className="mt-1 w-full rounded-2xl border border-gray-200 bg-gray-50 px-3 py-2.5 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none disabled:opacity-50"
          />
          <p className="mt-1 text-right text-[11px] text-gray-400">
            {title.length}/{MAX_TITLE_LENGTH}
          </p>
        </div>
        <div>
          <label
            htmlFor="feed-desc"
            className="text-xs font-extrabold text-gray-700"
          >
            Deskripsi
          </label>
          <textarea
            id="feed-desc"
            value={description}
            onChange={(e) => onDescriptionChange(e.target.value)}
            disabled={uploading}
            maxLength={MAX_DESC_LENGTH}
            placeholder="Ceritakan pengalamanmu..."
            rows={4}
            className="mt-1 w-full rounded-2xl border border-gray-200 bg-gray-50 px-3 py-2.5 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none disabled:opacity-50"
          />
          <p className="mt-1 text-right text-[11px] text-gray-400">
            {description.length}/{MAX_DESC_LENGTH}
          </p>
        </div>
      </div>

      <div className="space-y-3 rounded-3xl border border-gray-100 bg-white p-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 className="text-xs font-extrabold text-gray-700">Pin Produk</h2>
            <p className="mt-1 text-[11px] leading-relaxed text-gray-500">
              Pilih produk dari pesanan yang sudah kamu terima.
            </p>
          </div>
          <button
            type="button"
            onClick={onOpenProductPicker}
            disabled={uploading || productsLoading}
            className="rounded-full bg-natalo-600 px-3 py-2 text-[11px] font-extrabold text-white transition active:scale-95 disabled:bg-gray-300"
          >
            {productsLoading ? "Memuat" : selectedProduct ? "Ganti" : "Pilih"}
          </button>
        </div>

        {selectedProduct ? (
          <div className="flex items-center gap-3 rounded-2xl border border-natalo-100 bg-natalo-50 p-2.5">
            <div className="grid h-12 w-12 shrink-0 place-items-center rounded-xl bg-white text-natalo-600">
              <FiPackage className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="line-clamp-2 text-xs font-extrabold text-gray-900">
                {selectedProduct.name}
              </p>
              <p className="mt-0.5 text-[11px] font-semibold text-gray-500">
                Dibeli {formatDate(selectedProduct.purchasedAt)}
              </p>
            </div>
            <button
              type="button"
              onClick={onClearProduct}
              disabled={uploading}
              aria-label="Hapus produk pin"
              className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-white text-gray-500 disabled:opacity-50"
            >
              <FiX className="h-4 w-4" />
            </button>
          </div>
        ) : (
          <p className="rounded-2xl bg-gray-50 p-3 text-xs leading-relaxed text-gray-500">
            Opsional. Produk yang dipilih akan tampil sebagai chip di feed dan
            membantu pembeli lain langsung melihat produk yang kamu pakai.
          </p>
        )}
      </div>

      {/* Moderation notice */}
      <div className="rounded-2xl bg-amber-50 p-3 text-xs leading-relaxed text-amber-800">
        Video kamu akan direview admin maksimal 1x24 jam sebelum tampil di tab
        Komunitas. Pastikan konten menampilkan hewan peliharaan dan tidak
        mempromosikan produk kompetitor.
      </div>

      {uploading && (
        <UploadProgressView
          stage={processingStage}
          progress={processingProgress}
          label={uploadProgress || "Memproses video..."}
        />
      )}

      {error && (
        <p className="rounded-2xl bg-red-50 p-3 text-sm font-bold text-red-700">
          {error}
        </p>
      )}

      {/* CTA */}
      <button
        type="button"
        onClick={onSubmit}
        disabled={uploading || title.trim().length < 3}
        className="sticky bottom-4 w-full rounded-full bg-natalo-600 py-3.5 text-sm font-extrabold text-white shadow-lg transition active:scale-[0.98] disabled:cursor-not-allowed disabled:bg-gray-300"
      >
        {uploading ? uploadProgress || "Mengunggah..." : "Upload Video"}
      </button>

      <ProductPickerSheet
        open={productPickerOpen}
        products={pinnableProducts}
        selectedProductId={selectedProduct?.productId ?? null}
        loading={productsLoading}
        onClose={onCloseProductPicker}
        onSelect={onSelectProduct}
      />
    </div>
  );
}

function UploadProgressView({
  stage,
  progress,
  label,
}: {
  stage: ProcessingStage;
  progress: number;
  label: string;
}) {
  const stageText =
    stage === "compressing"
      ? "Memproses video 1/3"
      : stage === "uploading"
        ? "Mengunggah 2/3"
        : stage === "submitting"
          ? "Menyimpan 3/3"
          : "Menyiapkan";
  const showBar = stage === "compressing";

  return (
    <div className="rounded-2xl border border-natalo-100 bg-natalo-50 p-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-xs font-black text-natalo-800">{stageText}</p>
          <p className="mt-1 text-xs font-semibold text-natalo-700">{label}</p>
        </div>
        <div className="h-7 w-7 shrink-0 animate-spin rounded-full border-2 border-natalo-200 border-t-natalo-700" />
      </div>
      {showBar && (
        <div className="mt-3">
          <div className="h-2 overflow-hidden rounded-full bg-white">
            <div
              className="h-full rounded-full bg-natalo-600 transition-[width]"
              style={{ width: `${progress}%` }}
            />
          </div>
          <p className="mt-2 text-right text-[11px] font-black text-natalo-700">
            {progress}%
          </p>
        </div>
      )}
      <p className="mt-2 text-[11px] leading-relaxed text-natalo-700/80">
        Proses kompresi bisa memakan 10-30 detik, tergantung performa HP.
      </p>
    </div>
  );
}

function ProductPickerSheet({
  open,
  products,
  selectedProductId,
  loading,
  onClose,
  onSelect,
}: {
  open: boolean;
  products: PinnableProduct[];
  selectedProductId: string | null;
  loading: boolean;
  onClose: () => void;
  onSelect: (product: PinnableProduct) => void;
}) {
  return (
    <BottomSheet open={open} onClose={onClose} title="Pilih Produk">
      <div className="space-y-3">
        {loading && (
          <p className="py-8 text-center text-xs font-bold text-gray-400">
            Memuat produk...
          </p>
        )}
        {!loading && products.length === 0 && (
          <div className="rounded-2xl bg-gray-50 p-4 text-center">
            <p className="text-sm font-extrabold text-gray-700">
              Belum ada produk yang bisa di-pin
            </p>
            <p className="mt-1 text-xs leading-relaxed text-gray-500">
              Produk akan muncul setelah pesanan kamu selesai dan berstatus
              diterima.
            </p>
          </div>
        )}
        {products.map((product) => {
          const selected = product.productId === selectedProductId;
          return (
            <button
              key={`${product.productId}-${product.orderNumber}`}
              type="button"
              onClick={() => onSelect(product)}
              className={`flex w-full items-center gap-3 rounded-2xl border p-3 text-left transition active:bg-gray-50 ${
                selected
                  ? "border-natalo-500 bg-natalo-50"
                  : "border-gray-100 bg-white"
              }`}
            >
              <div className="grid h-14 w-14 shrink-0 place-items-center rounded-xl bg-gray-100 text-natalo-600">
                <FiPackage className="h-5 w-5" />
              </div>
              <div className="min-w-0 flex-1">
                <p className="line-clamp-2 text-sm font-extrabold text-gray-900">
                  {product.name}
                </p>
                <p className="mt-0.5 text-xs font-black text-natalo-600">
                  {formatRupiah(product.price)}
                </p>
                <p className="mt-0.5 text-[11px] font-semibold text-gray-500">
                  Dibeli {formatDate(product.purchasedAt)}
                </p>
              </div>
              {selected && (
                <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-natalo-600 text-white">
                  <FiCheck className="h-4 w-4" />
                </span>
              )}
            </button>
          );
        })}
      </div>
    </BottomSheet>
  );
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}
