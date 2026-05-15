"use client";

/**
 * Flow post Feed Natalo — video short 1–45 detik.
 *
 *   1. Pilih Video      → empty preview + Galeri/Kamera cards
 *   2. Preview Video    → cek hasil, Ganti Video / Putar Ulang
 *   3. Trim Video       → timeline + filmstrip + handle kiri/kanan
 *   4. Detail Postingan → caption (500), tag produk, info pet
 *   5. Menunggu Review  → success + Kembali ke Feed / Lihat Postingan
 *
 * Setiap step adalah layar penuh dengan transisi slide native-like.
 * Backend tetap pakai pipeline Bunny direct upload yang sudah ada
 * (POST /api/feed/bunny/upload-url → PUT raw bytes).
 */

import { useRouter } from "next/navigation";
import Image from "next/image";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  FiArrowLeft,
  FiCamera,
  FiCheck,
  FiImage,
  FiInfo,
  FiPackage,
  FiPlay,
  FiRotateCcw,
  FiShield,
  FiVideo,
  FiVolume2,
  FiVolumeX,
  FiX,
} from "react-icons/fi";
import { BottomSheet } from "@/components/BottomSheet";
import { FeedUploadSuccessLottie } from "@/components/feed/FeedUploadSuccessLottie";
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

const MAX_CAPTION_LENGTH = 500;
const ACCEPT_VIDEO = "video/mp4,video/quicktime,video/*";
const THUMBNAIL_BACKGROUND_TIMEOUT_MS = 5000;
const FILMSTRIP_FRAMES = 7;

type Step =
  | "pick"
  | "preview"
  | "trim"
  | "detail"
  | "success";

type Direction = "forward" | "back";

type PetType = "cat" | "dog" | "other" | null;

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

  // ── Step machine ──────────────────────────────────────────────────
  const [step, setStep] = useState<Step>("pick");
  const [direction, setDirection] = useState<Direction>("forward");

  const goNext = useCallback((target: Step) => {
    setDirection("forward");
    setStep(target);
    void hapticTap();
  }, []);
  const goBack = useCallback((target: Step) => {
    setDirection("back");
    setStep(target);
  }, []);

  // ── Video state ───────────────────────────────────────────────────
  const galleryInputRef = useRef<HTMLInputElement>(null);
  const cameraInputRef = useRef<HTMLInputElement>(null);
  const thumbnailJobRef = useRef(0);
  const [file, setFile] = useState<File | null>(null);
  const [filePreviewUrl, setFilePreviewUrl] = useState<string | null>(null);
  const [metadata, setMetadata] = useState<VideoMetadata | null>(null);
  const [thumbnailPreviewUrl, setThumbnailPreviewUrl] = useState<string | null>(null);
  const [thumbnailIsFallback, setThumbnailIsFallback] = useState(false);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzingLabel, setAnalyzingLabel] = useState("Menyiapkan video...");
  const [pickError, setPickError] = useState<string | null>(null);

  // Trim
  const [trimStart, setTrimStart] = useState(0);
  const [trimEnd, setTrimEnd] = useState(USER_VIDEO_CONFIG.maxDuration);
  const finalDuration = Math.max(0, trimEnd - trimStart);
  const trimValid =
    finalDuration >= USER_VIDEO_CONFIG.minDuration &&
    finalDuration <= USER_VIDEO_CONFIG.maxDuration;

  // Caption / tag / pet
  const [caption, setCaption] = useState("");
  const [selectedProduct, setSelectedProduct] = useState<PinnableProduct | null>(
    null,
  );
  const [productPickerOpen, setProductPickerOpen] = useState(false);
  const [pinnableProducts, setPinnableProducts] = useState<PinnableProduct[]>([]);
  const [productsLoading, setProductsLoading] = useState(false);
  const [petType, setPetType] = useState<PetType>(null);

  // Upload
  const [uploading, setUploading] = useState(false);
  const [uploadLabel, setUploadLabel] = useState("");
  const [uploadProgress, setUploadProgress] = useState(0);
  const [uploadStage, setUploadStage] = useState<
    "submitting" | "trimming" | "uploading" | null
  >(null);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [resultPostId, setResultPostId] = useState<string | null>(null);

  // ── Cleanup blob URLs ─────────────────────────────────────────────
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

  // ── Load pinnable products lazily (need them for Detail step) ────
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

  function resetVideo() {
    thumbnailJobRef.current += 1;
    if (filePreviewUrl) URL.revokeObjectURL(filePreviewUrl);
    if (thumbnailPreviewUrl) URL.revokeObjectURL(thumbnailPreviewUrl);
    setFile(null);
    setFilePreviewUrl(null);
    setMetadata(null);
    setThumbnailPreviewUrl(null);
    setThumbnailIsFallback(false);
    setTrimStart(0);
    setTrimEnd(USER_VIDEO_CONFIG.maxDuration);
  }

  function regenerateThumbnailAtTime(
    picked: File,
    meta: VideoMetadata,
    timeSec: number,
    jobId: number,
  ) {
    void extractVideoThumbnailSafe(picked, meta, {
      // Frame trim-start (offset kecil 0.1s supaya tidak nyangkut keyframe
      // sebelum trim-start yang kadang hitam). Clamp dengan durasi total.
      targetTimeSec: Math.min(
        Math.max(0.1, timeSec + 0.1),
        Math.max(0.1, meta.durationSec - 0.05),
      ),
      maxWidth: 480,
      timeoutMs: THUMBNAIL_BACKGROUND_TIMEOUT_MS,
      onError: (thumbnailError) => {
        console.info("[feed-video] retrim thumbnail fallback", {
          error:
            thumbnailError instanceof Error
              ? { name: thumbnailError.name, message: thumbnailError.message }
              : { message: String(thumbnailError) },
        });
      },
    })
      .then((thumb) => {
        if (thumbnailJobRef.current !== jobId) return;
        const prev = thumbnailPreviewUrl;
        setThumbnailPreviewUrl(URL.createObjectURL(thumb.blob));
        setThumbnailIsFallback(thumb.usedFallback);
        // Revoke setelah React swap supaya tidak race dengan <Image> yang
        // masih pegang URL lama.
        if (prev) {
          setTimeout(() => URL.revokeObjectURL(prev), 500);
        }
      })
      .catch(() => {
        // Thumbnail lama tetap dipakai — no-op.
      });
  }

  function generateThumbnailInBackground(
    picked: File,
    meta: VideoMetadata,
    jobId: number,
  ) {
    void extractVideoThumbnailSafe(picked, meta, {
      targetTimeSec: Math.min(1, Math.max(0.5, meta.durationSec * 0.25)),
      maxWidth: 480,
      timeoutMs: THUMBNAIL_BACKGROUND_TIMEOUT_MS,
      onError: (thumbnailError) => {
        console.info("[feed-video] thumbnail fallback", {
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
    })
      .then((thumb) => {
        if (thumbnailJobRef.current !== jobId) return;
        setThumbnailPreviewUrl(URL.createObjectURL(thumb.blob));
        setThumbnailIsFallback(thumb.usedFallback);
      })
      .catch((thumbnailError) => {
        console.info("[feed-video] thumbnail skipped", {
          fileName: picked.name,
          error:
            thumbnailError instanceof Error
              ? {
                  name: thumbnailError.name,
                  message: thumbnailError.message,
                  stack: thumbnailError.stack,
                }
              : { message: String(thumbnailError) },
        });
      });
  }

  async function handleFilePick(picked: File | null) {
    if (!picked) return;
    resetVideo();
    setPickError(null);

    if (!picked.type.startsWith("video/")) {
      setPickError("Format video belum didukung.");
      void hapticWarning();
      return;
    }
    if (picked.size > MAX_SOURCE_VIDEO_SIZE) {
      setPickError(
        `Ukuran video terlalu besar (${formatFileSize(
          picked.size,
        )}). Maksimal ${formatFileSize(MAX_SOURCE_VIDEO_SIZE)}.`,
      );
      void hapticWarning();
      return;
    }

    const pickedPreviewUrl = URL.createObjectURL(picked);
    const jobId = thumbnailJobRef.current + 1;
    thumbnailJobRef.current = jobId;
    setFile(picked);
    setFilePreviewUrl(pickedPreviewUrl);
    setAnalyzing(true);
    setAnalyzingLabel("Memeriksa durasi video...");

    try {
      const meta = await readVideoMetadata(picked);
      setMetadata(meta);

      if (
        meta.durationSec < USER_VIDEO_CONFIG.minDuration ||
        meta.durationSec > USER_VIDEO_CONFIG.maxDuration
      ) {
        resetVideo();
        setPickError("Video harus berdurasi 1–45 detik.");
        void hapticWarning();
        setAnalyzing(false);
        return;
      }

      // Seed trim range from the valid source clip; no compression/transcode here.
      setTrimStart(0);
      setTrimEnd(Math.min(meta.durationSec, USER_VIDEO_CONFIG.maxDuration));

      setAnalyzing(false);
      goNext("preview");
      generateThumbnailInBackground(picked, meta, jobId);
    } catch (err) {
      resetVideo();
      setPickError(
        "Video belum bisa digunakan. Coba pilih video lain.",
      );
      void hapticWarning();
    } finally {
      setAnalyzing(false);
    }
  }

  async function handleSubmit() {
    if (!file || !metadata) return;
    if (uploading) return;
    setSubmitError(null);
    setUploading(true);
    setUploadStage("submitting");
    setUploadProgress(0);
    setUploadLabel("Menyiapkan unggahan...");

    try {
      // 1) Buat record di Bunny + FeedPost row.
      const urlRes = await fetch("/api/feed/bunny/upload-url", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: caption.trim().slice(0, 200),
          description: caption.trim() || null,
          petType: petType ?? null,
          productIds: selectedProduct ? [selectedProduct.productId] : [],
        }),
      });
      const urlData = (await urlRes.json().catch(() => ({}))) as {
        error?: string;
        postId?: string;
        videoGuid?: string;
        uploadUrl?: string;
        uploadHeaders?: Record<string, string>;
      };
      if (!urlRes.ok || !urlData.uploadUrl) {
        throw new Error(urlData.error ?? "Gagal menyiapkan unggahan.");
      }

      // 2) Trim source kalau user pilih sub-range. Else skip — upload raw.
      let uploadBlob: Blob = file;
      const wantsTrim =
        trimStart > 0.1 || finalDuration < metadata.durationSec - 0.1;
      if (wantsTrim) {
        setUploadStage("trimming");
        setUploadProgress(0);
        setUploadLabel("Memotong video...");
        const { trimVideo } = await import("@/lib/feed/video-trimmer");
        uploadBlob = await trimVideo(file, {
          trimStartSec: trimStart,
          trimDurationSec: finalDuration,
          onProgress: setUploadProgress,
        });
      }

      // 3) PUT bytes ke Bunny.
      setUploadStage("uploading");
      setUploadProgress(0);
      setUploadLabel("Mengunggah video...");
      await uploadToBunnyWithProgress({
        uploadUrl: urlData.uploadUrl,
        headers: urlData.uploadHeaders ?? {},
        body: uploadBlob,
        onProgress: setUploadProgress,
      });

      setResultPostId(urlData.postId ?? null);
      void hapticSuccess();
      setDirection("forward");
      setStep("success");
    } catch (err) {
      setSubmitError(
        err instanceof Error ? err.message : "Upload gagal. Coba lagi.",
      );
      void hapticWarning();
    } finally {
      setUploading(false);
      setUploadStage(null);
      setUploadProgress(0);
      setUploadLabel("");
    }
  }

  function handleCloseFlow() {
    // Kembali ke Feed — bersihkan stack supaya tidak menumpuk.
    router.replace("/feed");
  }

  // ── Render ────────────────────────────────────────────────────────
  return (
    <div className="relative min-h-[100dvh] w-full overflow-x-hidden bg-black text-white">
      {/* Hidden inputs — satu untuk galeri, satu untuk kamera. */}
      <input
        ref={galleryInputRef}
        type="file"
        accept={ACCEPT_VIDEO}
        className="hidden"
        onChange={(e) => void handleFilePick(e.target.files?.[0] ?? null)}
      />
      <input
        ref={cameraInputRef}
        type="file"
        accept={ACCEPT_VIDEO}
        capture="environment"
        className="hidden"
        onChange={(e) => void handleFilePick(e.target.files?.[0] ?? null)}
      />

      <StepFrame stepKey={step} direction={direction}>
        {step === "pick" && (
          <PickScreen
            analyzing={analyzing}
            analyzingLabel={analyzingLabel}
            error={pickError}
            onClose={handleCloseFlow}
            onOpenGallery={() => galleryInputRef.current?.click()}
            onOpenCamera={() => cameraInputRef.current?.click()}
          />
        )}
        {step === "preview" && filePreviewUrl && metadata && (
          <PreviewScreen
            videoSrc={filePreviewUrl}
            durationSec={metadata.durationSec}
            onBack={() => {
              resetVideo();
              goBack("pick");
            }}
            onChangeVideo={() => galleryInputRef.current?.click()}
            onOpenGallery={() => galleryInputRef.current?.click()}
            onOpenCamera={() => cameraInputRef.current?.click()}
            onNext={() => goNext("trim")}
          />
        )}
        {step === "trim" && filePreviewUrl && metadata && (
          <TrimScreen
            videoSrc={filePreviewUrl}
            durationSec={metadata.durationSec}
            trimStart={trimStart}
            trimEnd={trimEnd}
            finalDuration={finalDuration}
            isValid={trimValid}
            onTrimStartChange={(v) => {
              const next = Math.max(0, Math.min(v, trimEnd - 1));
              setTrimStart(next);
            }}
            onTrimEndChange={(v) => {
              const maxAllowed = Math.min(
                metadata.durationSec,
                trimStart + USER_VIDEO_CONFIG.maxDuration,
              );
              const next = Math.max(trimStart + 1, Math.min(v, maxAllowed));
              setTrimEnd(next);
            }}
            onReset={() => {
              setTrimStart(0);
              setTrimEnd(
                Math.min(metadata.durationSec, USER_VIDEO_CONFIG.maxDuration),
              );
            }}
            onBack={() => goBack("preview")}
            onNext={() => {
              // Regenerate thumbnail dari trim-start frame supaya thumbnail
              // di success + admin review match konten yang akan tayang
              // (bukan frame yang user potong di awal). Background — kalau
              // gagal, thumbnail sebelumnya tetap dipakai.
              if (file && metadata) {
                const jobId = thumbnailJobRef.current + 1;
                thumbnailJobRef.current = jobId;
                regenerateThumbnailAtTime(file, metadata, trimStart, jobId);
              }
              goNext("detail");
            }}
          />
        )}
        {step === "detail" && filePreviewUrl && (
          <DetailScreen
            videoPreviewUrl={filePreviewUrl}
            thumbnailPreviewUrl={thumbnailPreviewUrl}
            thumbnailIsFallback={thumbnailIsFallback}
            finalDuration={finalDuration}
            caption={caption}
            onCaptionChange={setCaption}
            selectedProduct={selectedProduct}
            onOpenProductPicker={() => setProductPickerOpen(true)}
            onClearProduct={() => setSelectedProduct(null)}
            petType={petType}
            onPetChange={setPetType}
            uploading={uploading}
            uploadStage={uploadStage}
            uploadProgress={uploadProgress}
            uploadLabel={uploadLabel}
            submitError={submitError}
            onBack={() => goBack("trim")}
            onSubmit={() => void handleSubmit()}
          />
        )}
        {step === "success" && (
          <SuccessScreen
            thumbnailPreviewUrl={thumbnailPreviewUrl}
            finalDuration={finalDuration}
            postId={resultPostId}
            onBackToFeed={handleCloseFlow}
            onViewMyPosts={() => router.replace("/akun")}
          />
        )}
      </StepFrame>

      <ProductPickerSheet
        open={productPickerOpen}
        products={pinnableProducts}
        selectedProductId={selectedProduct?.productId ?? null}
        loading={productsLoading}
        onClose={() => setProductPickerOpen(false)}
        onSelect={(product) => {
          setSelectedProduct(product);
          setProductPickerOpen(false);
        }}
      />
    </div>
  );
}

// ── Step frame — native-like slide transitions ──────────────────────

function StepFrame({
  stepKey,
  direction,
  children,
}: {
  stepKey: Step;
  direction: Direction;
  children: React.ReactNode;
}) {
  // Key the wrapper on stepKey so each enter triggers the slide animation.
  const animClass =
    direction === "forward"
      ? "feed-step-enter-forward"
      : "feed-step-enter-back";

  return (
    <>
      <div key={stepKey} className={`${animClass} min-h-[100dvh]`}>
        {children}
      </div>
      <style>{`
        .feed-step-enter-forward {
          animation: feed-step-enter-forward 300ms cubic-bezier(0.22, 1, 0.36, 1) both;
        }
        .feed-step-enter-back {
          animation: feed-step-enter-back 280ms cubic-bezier(0.22, 1, 0.36, 1) both;
        }
        @keyframes feed-step-enter-forward {
          from {
            opacity: 0.85;
            transform: translate3d(100%, 0, 0);
          }
          to {
            opacity: 1;
            transform: translate3d(0, 0, 0);
          }
        }
        @keyframes feed-step-enter-back {
          from {
            opacity: 0.85;
            transform: translate3d(-100%, 0, 0);
          }
          to {
            opacity: 1;
            transform: translate3d(0, 0, 0);
          }
        }
        @media (prefers-reduced-motion: reduce) {
          .feed-step-enter-forward,
          .feed-step-enter-back {
            animation: none !important;
          }
        }
      `}</style>
    </>
  );
}

// ── Header ──────────────────────────────────────────────────────────

function FlowHeader({
  title,
  leftSlot,
  rightSlot,
  sticky = false,
}: {
  title: string;
  leftSlot: React.ReactNode;
  rightSlot: React.ReactNode;
  sticky?: boolean;
}) {
  return (
    <header
      className={`grid shrink-0 grid-cols-[48px_1fr_auto] items-center gap-2 px-4 pb-3 pt-[calc(env(safe-area-inset-top)+10px)] ${
        sticky
          ? "sticky top-0 z-30 border-b border-white/10 bg-black/95 backdrop-blur"
          : ""
      }`}
    >
      <div className="flex justify-start">{leftSlot}</div>
      <h1 className="text-center text-[15px] font-black tracking-wide">
        {title}
      </h1>
      <div className="flex justify-end">{rightSlot}</div>
    </header>
  );
}

function CloseButton({
  label = "Tutup",
  onClick,
}: {
  label?: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      className="grid h-10 w-10 place-items-center rounded-full text-white/90 transition active:bg-white/10"
    >
      <FiX className="h-5 w-5" />
    </button>
  );
}

function BackButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="Kembali"
      className="grid h-10 w-10 place-items-center rounded-full text-white/90 transition active:bg-white/10"
    >
      <FiArrowLeft className="h-5 w-5" />
    </button>
  );
}

function NextButton({
  onClick,
  disabled,
  label = "Next",
}: {
  onClick: () => void;
  disabled?: boolean;
  label?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={`rounded-full px-4 py-2 text-sm font-black transition active:scale-[0.97] ${
        disabled
          ? "cursor-not-allowed bg-white/10 text-white/35"
          : "bg-natalo-600 text-white shadow-[0_6px_16px_rgba(30,95,191,0.45)]"
      }`}
    >
      {label}
    </button>
  );
}

// ── Step 1: Pilih Video ─────────────────────────────────────────────

function PickScreen({
  analyzing,
  analyzingLabel,
  error,
  onClose,
  onOpenGallery,
  onOpenCamera,
}: {
  analyzing: boolean;
  analyzingLabel: string;
  error: string | null;
  onClose: () => void;
  onOpenGallery: () => void;
  onOpenCamera: () => void;
}) {
  return (
    <div className="flex h-[100dvh] min-h-[100dvh] flex-col overflow-hidden bg-black text-white">
      <FlowHeader
        title="Pilih Video"
        leftSlot={<CloseButton onClick={onClose} />}
        rightSlot={
          <NextButton onClick={() => undefined} disabled label="Next" />
        }
        sticky
      />

      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-[calc(32px+env(safe-area-inset-bottom))] [-webkit-overflow-scrolling:touch]">
        {/* Large empty preview card */}
        <div className="mx-auto mt-2 max-w-md">
          <button
            type="button"
            onClick={onOpenGallery}
            disabled={analyzing}
            className="group relative grid w-full place-items-center overflow-hidden rounded-[26px] border border-dashed border-white/15 bg-[#0d0f13] px-6 py-12 text-center transition active:scale-[0.99] disabled:opacity-60"
            style={{ aspectRatio: "9 / 11" }}
          >
            <div className="flex flex-col items-center gap-3">
              <span className="grid h-16 w-16 place-items-center rounded-2xl bg-natalo-600/15 text-natalo-300 ring-1 ring-natalo-500/30">
                <FiVideo className="h-7 w-7" />
              </span>
              <div>
                <p className="text-base font-black text-white">
                  Pilih video untuk Feed
                </p>
                <p className="mt-1 text-xs font-semibold text-white/55">
                  Durasi video 1–45 detik
                </p>
              </div>
              {analyzing && (
                <p className="mt-2 inline-flex items-center gap-2 text-xs font-bold text-natalo-200">
                  <span className="h-3 w-3 animate-spin rounded-full border-2 border-natalo-300/40 border-t-natalo-200" />
                  {analyzingLabel}
                </p>
              )}
            </div>
          </button>

          {/* Info chip */}
          <div className="mx-auto mt-4 inline-flex w-full items-center justify-center gap-2 rounded-full border border-natalo-500/25 bg-natalo-600/15 px-4 py-2 text-[12px] font-bold text-natalo-100">
            <FiInfo className="h-3.5 w-3.5" />
            Pilih video berdurasi 1–45 detik
          </div>

          {error && (
            <p className="mt-4 rounded-2xl border border-red-500/20 bg-red-500/10 p-3 text-center text-xs font-bold text-red-200">
              {error}
            </p>
          )}

          {/* Action cards */}
          <div className="mt-6 grid grid-cols-2 gap-3">
            <ActionCard
              icon={<FiImage className="h-5 w-5" />}
              title="Galeri"
              subtitle="Pilih video dari perangkat"
              onClick={onOpenGallery}
              disabled={analyzing}
            />
            <ActionCard
              icon={<FiCamera className="h-5 w-5" />}
              title="Kamera"
              subtitle="Rekam video baru"
              onClick={onOpenCamera}
              disabled={analyzing}
            />
          </div>

          {/* Info card */}
          <div className="mt-5 flex items-start gap-3 rounded-2xl border border-white/8 bg-white/[0.03] p-4">
            <span className="mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-full bg-natalo-600/20 text-natalo-200">
              <FiShield className="h-4 w-4" />
            </span>
            <div className="text-[12px] leading-relaxed">
              <p className="font-black text-white">1 video per posting</p>
              <p className="mt-0.5 text-white/55">
                Hanya bisa pilih satu video. Tidak ada multi-select atau grid
                terbaru.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function ActionCard({
  icon,
  title,
  subtitle,
  onClick,
  disabled,
}: {
  icon: React.ReactNode;
  title: string;
  subtitle: string;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="group flex flex-col items-start gap-2 rounded-2xl border border-white/8 bg-[#0d0f13] p-4 text-left transition active:scale-[0.98] disabled:opacity-60"
    >
      <span className="grid h-10 w-10 place-items-center rounded-xl bg-natalo-600/15 text-natalo-200 ring-1 ring-natalo-500/25">
        {icon}
      </span>
      <div>
        <p className="text-sm font-black text-white">{title}</p>
        <p className="mt-0.5 text-[11px] font-semibold text-white/50">
          {subtitle}
        </p>
      </div>
    </button>
  );
}

// ── Step 2: Preview Video ───────────────────────────────────────────

function PreviewScreen({
  videoSrc,
  durationSec,
  onBack,
  onChangeVideo,
  onOpenGallery,
  onOpenCamera,
  onNext,
}: {
  videoSrc: string;
  durationSec: number;
  onBack: () => void;
  onChangeVideo: () => void;
  onOpenGallery: () => void;
  onOpenCamera: () => void;
  onNext: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [playing, setPlaying] = useState(false);
  // Start muted — autoplay policy di browser/WKWebView ngeblok audio
  // sebelum user gesture. Begitu user tap unmute, kita unmute.
  const [muted, setMuted] = useState(true);

  // Auto-play sekali saat masuk preview supaya user langsung lihat motion.
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    v.muted = true;
    v.play()
      .then(() => setPlaying(true))
      .catch(() => setPlaying(false));
    return () => {
      v.pause();
    };
  }, []);

  // Sync muted state ke element supaya tap unmute langsung kedengeran.
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    v.muted = muted;
  }, [muted]);

  function togglePlay() {
    const v = videoRef.current;
    if (!v) return;
    if (v.paused) {
      v.play()
        .then(() => setPlaying(true))
        .catch(() => {});
    } else {
      v.pause();
      setPlaying(false);
    }
  }

  function toggleMute() {
    setMuted((current) => {
      const next = !current;
      const v = videoRef.current;
      if (v) {
        v.muted = next;
        // Kalau user unmute saat video pause, sekalian start play —
        // user gesture sudah valid jadi audio kedengeran.
        if (!next && v.paused) {
          v.play()
            .then(() => setPlaying(true))
            .catch(() => {});
        }
      }
      return next;
    });
  }

  function restart() {
    const v = videoRef.current;
    if (!v) return;
    v.currentTime = 0;
    v.play()
      .then(() => setPlaying(true))
      .catch(() => {});
  }

  return (
    <div className="flex h-[100dvh] min-h-[100dvh] flex-col overflow-hidden bg-black text-white">
      <FlowHeader
        title="Preview Video"
        leftSlot={<CloseButton onClick={onBack} label="Kembali" />}
        rightSlot={<NextButton onClick={onNext} />}
        sticky
      />

      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pb-[calc(32px+env(safe-area-inset-bottom))] [-webkit-overflow-scrolling:touch]">
        <div className="mx-auto max-w-md pt-2">
          <div
            className="relative overflow-hidden rounded-[26px] bg-black/60 ring-1 ring-white/10"
            style={{ aspectRatio: "9 / 12" }}
          >
            <video
              ref={videoRef}
              src={videoSrc}
              className="h-full w-full object-cover"
              playsInline
              loop
              onPause={() => setPlaying(false)}
              onPlay={() => setPlaying(true)}
            />
            <button
              type="button"
              onClick={togglePlay}
              aria-label={playing ? "Pause" : "Play"}
              className="absolute inset-0 grid place-items-center"
            >
              {!playing && (
                <span className="grid h-16 w-16 place-items-center rounded-full bg-black/55 text-white backdrop-blur">
                  <FiPlay className="h-7 w-7" />
                </span>
              )}
            </button>
            <span className="absolute right-3 top-3 rounded-full bg-black/60 px-2.5 py-1 text-[11px] font-black tracking-wide backdrop-blur">
              {formatClock(durationSec)}
            </span>
            <button
              type="button"
              onClick={toggleMute}
              aria-label={muted ? "Nyalakan suara" : "Matikan suara"}
              className="absolute bottom-3 right-3 grid h-10 w-10 place-items-center rounded-full bg-black/60 text-white backdrop-blur transition active:scale-95"
            >
              {muted ? (
                <FiVolumeX className="h-4 w-4" />
              ) : (
                <FiVolume2 className="h-4 w-4" />
              )}
            </button>
          </div>

          <div className="mt-4 grid grid-cols-2 gap-3">
            <SecondaryAction
              icon={<FiVideo className="h-4 w-4" />}
              label="Ganti Video"
              onClick={onChangeVideo}
            />
            <SecondaryAction
              icon={<FiRotateCcw className="h-4 w-4" />}
              label="Putar Ulang"
              onClick={restart}
            />
          </div>

          <div className="mt-3 grid grid-cols-2 gap-3">
            <SecondaryAction
              icon={<FiImage className="h-4 w-4" />}
              label="Galeri"
              onClick={onOpenGallery}
              muted
            />
            <SecondaryAction
              icon={<FiCamera className="h-4 w-4" />}
              label="Kamera"
              onClick={onOpenCamera}
              muted
            />
          </div>

          <p className="mt-5 text-center text-[11px] font-semibold text-white/45">
            Cek video sebelum di-trim. Pastikan ini video yang benar.
          </p>
        </div>
      </div>
    </div>
  );
}

function SecondaryAction({
  icon,
  label,
  onClick,
  muted = false,
}: {
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
  muted?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex items-center justify-center gap-2 rounded-2xl px-4 py-3 text-[13px] font-black transition active:scale-[0.98] ${
        muted
          ? "border border-white/10 bg-white/[0.03] text-white/75"
          : "border border-white/12 bg-white/[0.06] text-white"
      }`}
    >
      {icon}
      {label}
    </button>
  );
}

// ── Step 3: Trim Video ──────────────────────────────────────────────

function TrimScreen({
  videoSrc,
  durationSec,
  trimStart,
  trimEnd,
  finalDuration,
  isValid,
  onTrimStartChange,
  onTrimEndChange,
  onReset,
  onBack,
  onNext,
}: {
  videoSrc: string;
  durationSec: number;
  trimStart: number;
  trimEnd: number;
  finalDuration: number;
  isValid: boolean;
  onTrimStartChange: (v: number) => void;
  onTrimEndChange: (v: number) => void;
  onReset: () => void;
  onBack: () => void;
  onNext: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [playing, setPlaying] = useState(false);
  const [muted, setMuted] = useState(true);

  // Loop preview dalam segment yang dipilih.
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    if (v.currentTime < trimStart || v.currentTime >= trimEnd) {
      v.currentTime = trimStart;
    }
  }, [trimStart, trimEnd]);

  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    v.muted = muted;
  }, [muted]);

  function togglePlay() {
    const v = videoRef.current;
    if (!v) return;
    if (v.paused) {
      if (v.currentTime < trimStart || v.currentTime >= trimEnd) {
        v.currentTime = trimStart;
      }
      v.play()
        .then(() => setPlaying(true))
        .catch(() => {});
    } else {
      v.pause();
      setPlaying(false);
    }
  }

  function toggleMute() {
    setMuted((current) => {
      const next = !current;
      const v = videoRef.current;
      if (v) {
        v.muted = next;
        if (!next && v.paused) {
          v.play()
            .then(() => setPlaying(true))
            .catch(() => {});
        }
      }
      return next;
    });
  }

  function onTimeUpdate() {
    const v = videoRef.current;
    if (!v) return;
    if (v.currentTime >= trimEnd) {
      v.currentTime = trimStart;
    }
  }

  const invalidMsg =
    finalDuration < USER_VIDEO_CONFIG.minDuration
      ? "Durasi terlalu pendek. Minimal 1 detik."
      : "Durasi terlalu panjang. Maksimal 45 detik.";

  return (
    <div className="flex h-[100dvh] min-h-[100dvh] flex-col overflow-hidden bg-black text-white">
      <FlowHeader
        title="Trim Video"
        leftSlot={<CloseButton onClick={onBack} label="Kembali" />}
        rightSlot={<NextButton onClick={onNext} disabled={!isValid} />}
        sticky
      />

      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pb-[calc(32px+env(safe-area-inset-bottom))] [-webkit-overflow-scrolling:touch]">
        <div className="mx-auto max-w-md pt-2">
          {/* Preview */}
          <div
            className="relative overflow-hidden rounded-[26px] bg-black/60 ring-1 ring-white/10"
            style={{ aspectRatio: "9 / 12" }}
          >
            <video
              ref={videoRef}
              src={videoSrc}
              className="h-full w-full object-cover"
              playsInline
              loop
              onPause={() => setPlaying(false)}
              onPlay={() => setPlaying(true)}
              onTimeUpdate={onTimeUpdate}
            />
            <button
              type="button"
              onClick={togglePlay}
              aria-label={playing ? "Pause" : "Play"}
              className="absolute inset-0 grid place-items-center"
            >
              {!playing && (
                <span className="grid h-14 w-14 place-items-center rounded-full bg-black/55 text-white backdrop-blur">
                  <FiPlay className="h-6 w-6" />
                </span>
              )}
            </button>
            <span className="absolute right-3 top-3 rounded-full bg-black/60 px-2.5 py-1 text-[11px] font-black tracking-wide backdrop-blur">
              {formatClock(durationSec)}
            </span>
            <button
              type="button"
              onClick={toggleMute}
              aria-label={muted ? "Nyalakan suara" : "Matikan suara"}
              className="absolute bottom-3 right-3 grid h-10 w-10 place-items-center rounded-full bg-black/60 text-white backdrop-blur transition active:scale-95"
            >
              {muted ? (
                <FiVolumeX className="h-4 w-4" />
              ) : (
                <FiVolume2 className="h-4 w-4" />
              )}
            </button>
          </div>

          <p className="mt-5 text-center text-[12px] font-semibold leading-relaxed text-white/55">
            Atur bagian video yang ingin diposting
            <br />
            <span className="font-black text-white/80">1–45 detik</span>
          </p>

          {/* Time markers */}
          <div className="mt-5 flex items-center justify-between px-1 text-[11px] font-black text-white/60">
            <span>{formatClock(trimStart)}</span>
            <span className="text-natalo-200">{formatClock(finalDuration)}</span>
            <span>{formatClock(durationSec)}</span>
          </div>

          {/* Filmstrip with handles */}
          <Filmstrip
            videoSrc={videoSrc}
            durationSec={durationSec}
            trimStart={trimStart}
            trimEnd={trimEnd}
            onTrimStartChange={onTrimStartChange}
            onTrimEndChange={onTrimEndChange}
          />

          {/* Selected duration / validation */}
          <p
            className={`mt-4 text-center text-[13px] font-black ${
              isValid ? "text-white" : "text-amber-300"
            }`}
          >
            {isValid ? (
              <>
                Durasi terpilih{" "}
                <span className="text-natalo-300">{formatClock(finalDuration)}</span>
              </>
            ) : (
              invalidMsg
            )}
          </p>

          {/* Action row */}
          <div className="mt-6 grid grid-cols-2 gap-3">
            <button
              type="button"
              onClick={onReset}
              className="rounded-full border border-white/12 bg-white/[0.04] py-3 text-sm font-black text-white/85 transition active:scale-[0.98]"
            >
              Reset
            </button>
            <button
              type="button"
              onClick={onNext}
              disabled={!isValid}
              className={`rounded-full py-3 text-sm font-black transition active:scale-[0.98] ${
                isValid
                  ? "bg-natalo-600 text-white shadow-[0_6px_18px_rgba(30,95,191,0.5)]"
                  : "cursor-not-allowed bg-white/10 text-white/35"
              }`}
            >
              Selesai
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function Filmstrip({
  videoSrc,
  durationSec,
  trimStart,
  trimEnd,
  onTrimStartChange,
  onTrimEndChange,
}: {
  videoSrc: string;
  durationSec: number;
  trimStart: number;
  trimEnd: number;
  onTrimStartChange: (v: number) => void;
  onTrimEndChange: (v: number) => void;
}) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [frames, setFrames] = useState<string[]>([]);

  // Generate filmstrip thumbnails sekali per videoSrc. Pakai canvas drawing
  // dari <video> element — ringan, tidak butuh ffmpeg.wasm.
  useEffect(() => {
    let cancelled = false;
    const urls: string[] = [];
    setFrames([]);

    const v = document.createElement("video");
    v.src = videoSrc;
    v.crossOrigin = "anonymous";
    v.muted = true;
    v.playsInline = true;
    v.preload = "auto";

    const cleanup = () => {
      try {
        v.src = "";
        v.load();
      } catch {}
    };

    v.onloadedmetadata = async () => {
      if (cancelled) return cleanup();
      const totalDur = Number.isFinite(v.duration) ? v.duration : durationSec;
      const canvas = document.createElement("canvas");
      const targetWidth = 96;
      const aspect = v.videoHeight && v.videoWidth ? v.videoHeight / v.videoWidth : 16 / 9;
      canvas.width = targetWidth;
      canvas.height = Math.round(targetWidth * aspect);
      const ctx = canvas.getContext("2d");
      if (!ctx) return cleanup();

      for (let i = 0; i < FILMSTRIP_FRAMES; i++) {
        if (cancelled) return cleanup();
        const t = (totalDur / FILMSTRIP_FRAMES) * (i + 0.5);
        try {
          await seekTo(v, Math.min(Math.max(0, t), Math.max(0, totalDur - 0.05)));
          ctx.drawImage(v, 0, 0, canvas.width, canvas.height);
          const dataUrl = canvas.toDataURL("image/jpeg", 0.7);
          urls.push(dataUrl);
          if (!cancelled) setFrames([...urls]);
        } catch {
          // Skip frame ini, lanjut.
        }
      }
      cleanup();
    };
    v.onerror = () => cleanup();

    return () => {
      cancelled = true;
      cleanup();
    };
  }, [videoSrc, durationSec]);

  // Position handles dalam %.
  const startPct = Math.max(0, Math.min(100, (trimStart / Math.max(0.001, durationSec)) * 100));
  const endPct = Math.max(0, Math.min(100, (trimEnd / Math.max(0.001, durationSec)) * 100));

  // Pointer drag.
  function startDrag(
    event: React.PointerEvent<HTMLDivElement>,
    handle: "start" | "end",
  ) {
    event.preventDefault();
    const track = trackRef.current;
    if (!track) return;
    const rect = track.getBoundingClientRect();
    const targetEl = event.currentTarget;
    try {
      targetEl.setPointerCapture(event.pointerId);
    } catch {}

    function compute(clientX: number) {
      const x = Math.max(rect.left, Math.min(rect.right, clientX));
      const pct = (x - rect.left) / rect.width;
      return pct * durationSec;
    }

    function onMove(e: PointerEvent) {
      const value = compute(e.clientX);
      if (handle === "start") onTrimStartChange(value);
      else onTrimEndChange(value);
    }
    function onUp() {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
    }
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);

    // Move once immediately.
    onMove(event.nativeEvent);
  }

  return (
    <div className="mt-3 select-none">
      <div
        ref={trackRef}
        className="relative h-16 overflow-hidden rounded-2xl bg-white/[0.04] ring-1 ring-white/10"
      >
        {/* Filmstrip frames */}
        <div className="absolute inset-0 flex">
          {Array.from({ length: FILMSTRIP_FRAMES }).map((_, i) => (
            <div key={i} className="relative h-full flex-1 overflow-hidden">
              {frames[i] ? (
                <img
                  src={frames[i]}
                  alt=""
                  className="h-full w-full object-cover opacity-90"
                />
              ) : (
                <div className="h-full w-full bg-[linear-gradient(90deg,#0a1530,#152a55,#0a1530)] opacity-70" />
              )}
            </div>
          ))}
        </div>

        {/* Dim overlay outside selected range */}
        <div
          className="absolute inset-y-0 left-0 bg-black/55 backdrop-blur-[1px]"
          style={{ width: `${startPct}%` }}
        />
        <div
          className="absolute inset-y-0 right-0 bg-black/55 backdrop-blur-[1px]"
          style={{ width: `${100 - endPct}%` }}
        />

        {/* Selected window border */}
        <div
          className="pointer-events-none absolute inset-y-0 border-y-[3px] border-natalo-400"
          style={{
            left: `${startPct}%`,
            width: `${Math.max(0, endPct - startPct)}%`,
          }}
        />

        {/* Left handle */}
        <div
          role="slider"
          aria-label="Mulai trim"
          aria-valuemin={0}
          aria-valuemax={durationSec}
          aria-valuenow={trimStart}
          onPointerDown={(e) => startDrag(e, "start")}
          className="absolute inset-y-0 flex w-6 -translate-x-1/2 cursor-ew-resize items-center justify-center"
          style={{ left: `${startPct}%` }}
        >
          <span className="h-full w-1.5 rounded-r bg-natalo-400" />
          <span className="absolute inset-y-1 left-1/2 grid w-3 -translate-x-1/2 place-items-center rounded-full bg-natalo-400">
            <span className="h-5 w-0.5 rounded bg-natalo-900/70" />
          </span>
        </div>
        {/* Right handle */}
        <div
          role="slider"
          aria-label="Akhir trim"
          aria-valuemin={0}
          aria-valuemax={durationSec}
          aria-valuenow={trimEnd}
          onPointerDown={(e) => startDrag(e, "end")}
          className="absolute inset-y-0 flex w-6 -translate-x-1/2 cursor-ew-resize items-center justify-center"
          style={{ left: `${endPct}%` }}
        >
          <span className="h-full w-1.5 rounded-l bg-natalo-400" />
          <span className="absolute inset-y-1 left-1/2 grid w-3 -translate-x-1/2 place-items-center rounded-full bg-natalo-400">
            <span className="h-5 w-0.5 rounded bg-natalo-900/70" />
          </span>
        </div>
      </div>
    </div>
  );
}

function seekTo(video: HTMLVideoElement, time: number) {
  return new Promise<void>((resolve, reject) => {
    const onSeeked = () => {
      video.removeEventListener("seeked", onSeeked);
      video.removeEventListener("error", onError);
      resolve();
    };
    const onError = () => {
      video.removeEventListener("seeked", onSeeked);
      video.removeEventListener("error", onError);
      reject(new Error("seek error"));
    };
    video.addEventListener("seeked", onSeeked);
    video.addEventListener("error", onError);
    try {
      video.currentTime = time;
    } catch (err) {
      reject(err);
    }
  });
}

// ── Step 4: Detail Postingan ────────────────────────────────────────

function DetailScreen({
  videoPreviewUrl,
  thumbnailPreviewUrl,
  thumbnailIsFallback,
  finalDuration,
  caption,
  onCaptionChange,
  selectedProduct,
  onOpenProductPicker,
  onClearProduct,
  petType,
  onPetChange,
  uploading,
  uploadStage,
  uploadProgress,
  uploadLabel,
  submitError,
  onBack,
  onSubmit,
}: {
  videoPreviewUrl: string;
  thumbnailPreviewUrl: string | null;
  thumbnailIsFallback: boolean;
  finalDuration: number;
  caption: string;
  onCaptionChange: (v: string) => void;
  selectedProduct: PinnableProduct | null;
  onOpenProductPicker: () => void;
  onClearProduct: () => void;
  petType: PetType;
  onPetChange: (v: PetType) => void;
  uploading: boolean;
  uploadStage: "submitting" | "trimming" | "uploading" | null;
  uploadProgress: number;
  uploadLabel: string;
  submitError: string | null;
  onBack: () => void;
  onSubmit: () => void;
}) {
  const realThumbnailUrl = thumbnailIsFallback ? null : thumbnailPreviewUrl;

  useEffect(() => {
    if (typeof document === "undefined") return;
    const roots = [
      document.documentElement,
      document.body,
      document.getElementById("__next"),
      document.getElementById("root"),
    ].filter(Boolean) as HTMLElement[];
    const previousBackgrounds = roots.map((node) => node.style.backgroundColor);
    roots.forEach((node) => {
      node.style.backgroundColor = "#000";
    });
    return () => {
      roots.forEach((node, index) => {
        node.style.backgroundColor = previousBackgrounds[index] ?? "";
      });
    };
  }, []);

  return (
    <div
      className="feed-create-detail-page flex h-[100dvh] min-h-[100dvh] flex-col overflow-hidden bg-black text-white"
      style={{ backgroundColor: "#000" }}
    >
      <FlowHeader
        title="Detail Postingan"
        leftSlot={<BackButton onClick={onBack} />}
        rightSlot={
          <NextButton
            onClick={onSubmit}
            disabled={uploading}
            label={uploading ? "Mengirim..." : "Posting"}
          />
        }
        sticky
      />

      <div
        className="min-h-0 flex-1 overflow-y-auto overscroll-contain bg-black px-4 pb-[calc(32px+env(safe-area-inset-bottom))] [-webkit-overflow-scrolling:touch]"
        style={{ backgroundColor: "#000" }}
      >
        <div className="mx-auto max-w-md space-y-4 pt-2">
          {/* Caption row + thumbnail */}
          <div className="flex gap-3 rounded-2xl border border-white/8 bg-white/[0.03] p-3">
            <div className="relative h-24 w-20 shrink-0 overflow-hidden rounded-xl bg-white/5">
              {realThumbnailUrl ? (
                <Image
                  src={realThumbnailUrl}
                  alt="Preview"
                  fill
                  sizes="80px"
                  className="object-cover"
                  unoptimized
                />
              ) : (
                <video
                  src={videoPreviewUrl}
                  className="h-full w-full object-cover"
                  muted
                  playsInline
                  preload="metadata"
                />
              )}
              <span className="absolute inset-0 bg-black/10" />
              <span className="absolute inset-0 grid place-items-center">
                <span className="grid h-8 w-8 place-items-center rounded-full bg-black/55 text-white backdrop-blur-sm">
                  <FiPlay className="ml-0.5 h-4 w-4" />
                </span>
              </span>
              <span className="absolute bottom-1 left-1 rounded bg-black/70 px-1.5 py-0.5 text-[10px] font-black">
                {formatClock(finalDuration)}
              </span>
            </div>
            <div className="flex flex-1 flex-col">
              <textarea
                value={caption}
                onChange={(e) =>
                  onCaptionChange(e.target.value.slice(0, MAX_CAPTION_LENGTH))
                }
                disabled={uploading}
                placeholder="Tulis caption..."
                rows={4}
                className="flex-1 resize-none bg-transparent text-sm font-medium leading-relaxed text-white placeholder:text-white/35 focus:outline-none disabled:opacity-50"
              />
              <p className="text-right text-[11px] font-bold text-white/40">
                {caption.length}/{MAX_CAPTION_LENGTH}
              </p>
            </div>
          </div>

          {/* Tag produk */}
          <section className="rounded-2xl border border-white/8 bg-white/[0.03] p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-black text-white">Tag Produk</h2>
              <button
                type="button"
                onClick={onOpenProductPicker}
                disabled={uploading}
                className="text-[12px] font-black text-natalo-300 transition active:opacity-70 disabled:opacity-50"
              >
                Ubah ›
              </button>
            </div>

            {selectedProduct ? (
              <div className="mt-3 flex items-center gap-3 rounded-xl bg-white/[0.04] p-2.5 ring-1 ring-white/8">
                <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-natalo-600/15 text-natalo-200 ring-1 ring-natalo-500/25">
                  <FiPackage className="h-5 w-5" />
                </div>
                <p className="line-clamp-2 flex-1 text-[13px] font-extrabold text-white">
                  {selectedProduct.name}
                </p>
                <button
                  type="button"
                  onClick={onClearProduct}
                  disabled={uploading}
                  aria-label="Hapus tag produk"
                  className="grid h-8 w-8 shrink-0 place-items-center rounded-full text-white/60 transition active:bg-white/10"
                >
                  <FiX className="h-4 w-4" />
                </button>
              </div>
            ) : (
              <p className="mt-2 text-[12px] leading-relaxed text-white/50">
                Opsional. Tag produk dari pesanan kamu agar pengguna lain bisa
                langsung lihat produknya.
              </p>
            )}
          </section>

          {/* Info Pet */}
          <section className="rounded-2xl border border-white/8 bg-white/[0.03] p-4">
            <h2 className="text-sm font-black text-white">Info Pet</h2>
            <div className="mt-3 flex flex-wrap gap-2">
              <PetChip
                active={petType === "cat"}
                label="Kucing"
                icon="🐱"
                onClick={() => onPetChange(petType === "cat" ? null : "cat")}
                disabled={uploading}
              />
              <PetChip
                active={petType === "dog"}
                label="Anjing"
                icon="🐶"
                onClick={() => onPetChange(petType === "dog" ? null : "dog")}
                disabled={uploading}
              />
              <PetChip
                active={petType === "other"}
                label="Lainnya"
                icon="•••"
                onClick={() => onPetChange(petType === "other" ? null : "other")}
                disabled={uploading}
              />
            </div>
          </section>

          {/* Review notice */}
          <div className="flex items-start gap-3 rounded-2xl border border-white/8 bg-white/[0.03] p-4">
            <span className="mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-full bg-natalo-600/20 text-natalo-200">
              <FiShield className="h-4 w-4" />
            </span>
            <p className="text-[12px] leading-relaxed text-white/65">
              Postingan akan ditinjau admin sebelum tayang.
            </p>
          </div>

          {uploading && (
            <div className="rounded-2xl border border-natalo-500/25 bg-natalo-600/10 p-4">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <p className="text-xs font-black text-natalo-100">
                    {uploadLabel || "Memproses..."}
                  </p>
                  <p className="mt-1 text-[11px] font-semibold text-natalo-200/80">
                    {uploadStage === "trimming"
                      ? "Sedang memotong video..."
                      : uploadStage === "uploading"
                        ? "Mengunggah ke cloud..."
                        : "Menyimpan postingan..."}
                  </p>
                </div>
                <div className="h-6 w-6 shrink-0 animate-spin rounded-full border-2 border-natalo-300/30 border-t-natalo-200" />
              </div>
              {(uploadStage === "trimming" || uploadStage === "uploading") && (
                <div className="mt-3 h-2 overflow-hidden rounded-full bg-white/10">
                  <div
                    className="h-full rounded-full bg-natalo-400 transition-[width]"
                    style={{ width: `${Math.max(0, Math.min(100, uploadProgress))}%` }}
                  />
                </div>
              )}
            </div>
          )}

          {submitError && (
            <p className="rounded-2xl border border-red-500/25 bg-red-500/10 p-3 text-center text-xs font-bold text-red-200">
              {submitError}
            </p>
          )}

          <button
            type="button"
            onClick={onSubmit}
            disabled={uploading}
            className={`w-full rounded-full py-3.5 text-sm font-black transition active:scale-[0.98] ${
              uploading
                ? "cursor-not-allowed bg-white/10 text-white/40"
                : "bg-natalo-600 text-white shadow-[0_6px_18px_rgba(30,95,191,0.45)]"
            }`}
          >
            {uploading ? uploadLabel || "Mengirim..." : "Posting"}
          </button>
        </div>
      </div>
    </div>
  );
}

function PetChip({
  active,
  label,
  icon,
  onClick,
  disabled,
}: {
  active: boolean;
  label: string;
  icon: string;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={`flex items-center gap-1.5 rounded-full px-3.5 py-2 text-[12px] font-black transition active:scale-[0.97] ${
        active
          ? "bg-natalo-600 text-white shadow-[0_4px_12px_rgba(30,95,191,0.45)]"
          : "border border-white/12 bg-white/[0.04] text-white/75"
      } ${disabled ? "opacity-60" : ""}`}
    >
      <span aria-hidden>{icon}</span>
      {label}
    </button>
  );
}

// ── Step 5: Menunggu Review ─────────────────────────────────────────

function SuccessScreen({
  thumbnailPreviewUrl,
  finalDuration,
  postId,
  onBackToFeed,
  onViewMyPosts,
}: {
  thumbnailPreviewUrl: string | null;
  finalDuration: number;
  postId: string | null;
  onBackToFeed: () => void;
  onViewMyPosts: () => void;
}) {
  return (
    <div className="flex min-h-[100dvh] flex-col bg-black text-white">
      <FlowHeader
        title=""
        leftSlot={<span />}
        rightSlot={<span />}
      />
      <div className="flex flex-1 flex-col items-center justify-center px-6 pb-[calc(40px+env(safe-area-inset-bottom))] text-center">
        <FeedUploadSuccessLottie />

        <h1 className="mt-2 text-xl font-black text-white">
          Postingan berhasil dikirim
        </h1>
        <p className="mt-2 max-w-xs text-sm font-medium leading-relaxed text-white/60">
          Postingan kamu sedang menunggu review admin.
        </p>

        {/* Preview card — selalu render. Pakai thumbnail user kalau berhasil
            di-generate, fallback dark gradient kalau gagal. Play icon dan
            duration badge selalu visible. */}
        <div className="relative mt-7 h-44 w-32 overflow-hidden rounded-2xl ring-1 ring-white/10">
          {thumbnailPreviewUrl ? (
            <Image
              src={thumbnailPreviewUrl}
              alt="Preview postingan"
              fill
              sizes="128px"
              className="object-cover"
              unoptimized
            />
          ) : (
            <div
              aria-hidden
              className="absolute inset-0 bg-[linear-gradient(135deg,#05070b_0%,#101827_55%,#1e5fbf_100%)]"
            />
          )}
          {/* Dark overlay tipis supaya play icon + duration tetap kebaca
              meski thumbnail terang. */}
          <div
            aria-hidden
            className="absolute inset-0 bg-black/15"
          />
          {/* Play icon center */}
          <div
            aria-hidden
            className="absolute inset-0 grid place-items-center"
          >
            <span className="grid h-11 w-11 place-items-center rounded-full bg-black/55 text-white backdrop-blur-sm">
              <FiPlay className="h-5 w-5" />
            </span>
          </div>
          {/* Duration badge bottom-left */}
          <span className="absolute bottom-2 left-2 rounded-md bg-black/70 px-2 py-0.5 text-[11px] font-black tracking-wide">
            {formatClock(finalDuration)}
          </span>
        </div>

        <div className="mt-10 w-full max-w-xs space-y-3">
          <button
            type="button"
            onClick={onBackToFeed}
            className="w-full rounded-full bg-natalo-600 py-3.5 text-sm font-black text-white shadow-[0_6px_18px_rgba(30,95,191,0.45)] transition active:scale-[0.98]"
          >
            Kembali ke Feed
          </button>
          <button
            type="button"
            onClick={onViewMyPosts}
            className="w-full rounded-full py-3 text-sm font-black text-white/80 transition active:bg-white/5"
          >
            Lihat Postingan Saya
          </button>
        </div>
        {postId && (
          <p className="mt-4 text-[10px] font-bold text-white/30">
            ID #{postId.slice(0, 8)}
          </p>
        )}
      </div>
    </div>
  );
}

// ── Product picker bottom sheet ─────────────────────────────────────

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
    <BottomSheet open={open} onClose={onClose} title="Tag Produk">
      <div className="space-y-3">
        {loading && (
          <p className="py-8 text-center text-xs font-bold text-gray-400">
            Memuat produk...
          </p>
        )}
        {!loading && products.length === 0 && (
          <div className="rounded-2xl bg-gray-50 p-4 text-center">
            <p className="text-sm font-extrabold text-gray-700">
              Belum ada produk yang bisa di-tag
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

// ── Helpers ─────────────────────────────────────────────────────────

function formatClock(sec: number) {
  const total = Math.max(0, Math.round(sec));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

/**
 * PUT bytes ke Bunny — XHR untuk upload progress (fetch tidak punya
 * upload-progress di iOS WKWebView).
 */
function uploadToBunnyWithProgress(params: {
  uploadUrl: string;
  headers: Record<string, string>;
  body: Blob;
  onProgress?: (pct: number) => void;
}): Promise<void> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", params.uploadUrl, true);
    for (const [key, value] of Object.entries(params.headers)) {
      xhr.setRequestHeader(key, value);
    }
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable && params.onProgress) {
        params.onProgress(Math.round((event.loaded / event.total) * 100));
      }
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve();
      else reject(new Error(`Bunny upload failed (HTTP ${xhr.status})`));
    };
    xhr.onerror = () => reject(new Error("Bunny upload network error"));
    xhr.onabort = () => reject(new Error("Bunny upload aborted"));
    xhr.send(params.body);
  });
}
