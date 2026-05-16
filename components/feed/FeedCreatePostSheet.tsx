"use client";

import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
  type RefObject,
} from "react";
import {
  FiAlertCircle,
  FiArrowLeft,
  FiCamera,
  FiCheck,
  FiClock,
  FiFilm,
  FiImage,
  FiInfo,
  FiPackage,
  FiPause,
  FiPlay,
  FiPlus,
  FiUploadCloud,
  FiX,
} from "react-icons/fi";
import { formatRupiah } from "@/lib/format";
import {
  createFallbackVideoThumbnail,
  extractVideoThumbnail,
  readVideoMetadata,
  type VideoMetadata,
} from "@/lib/feed/video-thumbnail";
import {
  formatFileSize,
  MAX_SOURCE_VIDEO_SIZE,
  USER_VIDEO_CONFIG,
} from "@/lib/feed/video-config";
import { hapticSuccess, hapticTap, hapticWarning } from "@/lib/native/haptics";
import { isIOS } from "@/lib/native-platform";
import { useFeedUpload } from "@/components/feed/FeedUploadProvider";
import { FeedUploadSuccessLottie } from "@/components/feed/FeedUploadSuccessLottie";
import { natToast } from "@/components/Toast";

// Source-of-truth lives in USER_VIDEO_CONFIG (lib/feed/video-config.ts).
// Mirror locally for terse references inside this component.
const MIN_VIDEO_DURATION = USER_VIDEO_CONFIG.minDuration;
const MAX_VIDEO_DURATION = USER_VIDEO_CONFIG.maxDuration;
const DURATION_RANGE_LABEL = `${MIN_VIDEO_DURATION}-${MAX_VIDEO_DURATION} detik`;
const MAX_CAPTION_LENGTH = 300;
const MAX_PINNED_PRODUCTS = 3;
// Gallery picker accepts format yang dipakai Feed user: MP4 dan MOV.
// Camera recorder (capture="environment") pakai accept terpisah "video/*"
// karena iOS WKFileUploadPanel crash kalau accept-list mengandung MIME yang
// tidak punya UTI mapping (mis. video/webm — iOS tidak support WebM native).
// Pakai "video/*" memberi WKWebView signal generic → UIImagePickerController
// langsung dibuka dengan mediaTypes = [kUTTypeMovie] dan iOS rekam dalam
// format native-nya sendiri (.mov / quicktime).
const ACCEPT_VIDEO_GALLERY = "video/mp4,video/quicktime";
const ACCEPT_VIDEO_CAMERA = "video/*";

type FlowStep = "pick" | "trim" | "detail" | "success" | "status";
type UploadStage = "compressing" | "uploading-video" | "uploading-thumbnail" | "submitting" | null;

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

type SelectedVideo = {
  file: File;
  previewUrl: string;
  thumbnailBlob: Blob;
  thumbnailUrl: string;
  thumbnailIsFallback: boolean;
  metadata: VideoMetadata;
};

type SubmittedPost = {
  id: string;
  status: string;
};

type Props = {
  open: boolean;
  onClose: () => void;
};

const PET_TYPES = [
  "🐶 Anjing",
  "🐱 Kucing",
  "🦜 Burung",
  "🐠 Ikan",
  "🐰 Lainnya",
];

export function FeedCreatePostSheet({ open, onClose }: Props) {
  const galleryInputRef = useRef<HTMLInputElement>(null);
  const cameraInputRef = useRef<HTMLInputElement>(null);
  const previewVideoRef = useRef<HTMLVideoElement>(null);
  const pickTokenRef = useRef(0);
  const [step, setStep] = useState<FlowStep>("pick");
  const [selectedVideo, setSelectedVideo] = useState<SelectedVideo | null>(null);
  const [selecting, setSelecting] = useState(false);
  const [videoError, setVideoError] = useState<string | null>(null);
  const [trimStart, setTrimStart] = useState(0);
  const [trimEnd, setTrimEnd] = useState(MAX_VIDEO_DURATION);
  const [isPlaying, setIsPlaying] = useState(false);
  const [caption, setCaption] = useState("");
  const [petType, setPetType] = useState<string | null>(null);
  const [petName, setPetName] = useState("");
  const [products, setProducts] = useState<PinnableProduct[]>([]);
  const [selectedProductIds, setSelectedProductIds] = useState<string[]>([]);
  const [productPickerOpen, setProductPickerOpen] = useState(false);
  const [productsLoading, setProductsLoading] = useState(false);
  const [productsLoaded, setProductsLoaded] = useState(false);
  const [productsError, setProductsError] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [uploadStage, setUploadStage] = useState<UploadStage>(null);
  const [uploadProgress, setUploadProgress] = useState(0);
  const feedUpload = useFeedUpload();
  const [submittedPost, setSubmittedPost] = useState<SubmittedPost | null>(null);

  const finalDuration = Math.max(0, trimEnd - trimStart);
  const hasValidFinalDuration =
    finalDuration >= MIN_VIDEO_DURATION && finalDuration <= MAX_VIDEO_DURATION;
  const selectedNeedsTrim =
    selectedVideo ? selectedVideo.metadata.durationSec > MAX_VIDEO_DURATION : false;
  const selectedTooShort =
    selectedVideo ? selectedVideo.metadata.durationSec < MIN_VIDEO_DURATION : false;
  const selectedCanContinue =
    Boolean(selectedVideo) && !selectedTooShort && (hasValidFinalDuration || selectedNeedsTrim);
  const canPost = Boolean(selectedVideo) && hasValidFinalDuration && !uploadStage;

  const selectedProducts = useMemo(
    () =>
      selectedProductIds
        .map((id) => products.find((product) => product.productId === id))
        .filter((product): product is PinnableProduct => Boolean(product)),
    [products, selectedProductIds],
  );

  useEffect(() => {
    if (!open) return;
    document.body.classList.add("nat-modal-open", "nat-scroll-locked");
    return () => {
      document.body.classList.remove("nat-modal-open", "nat-scroll-locked");
    };
  }, [open]);

  useEffect(() => {
    if (!open || productsLoaded) return;
    let cancelled = false;
    setProductsLoading(true);
    setProductsError(null);

    fetch("/api/feed/pinnable-products")
      .then(async (res) => {
        const data = await res.json().catch(() => ({}));
        if (!res.ok) {
          throw new Error(
            typeof data?.error === "string"
              ? data.error
              : "Gagal memuat riwayat pembelian.",
          );
        }
        return data as { products: PinnableProduct[] };
      })
      .then((data) => {
        if (cancelled) return;
        setProducts(data.products ?? []);
        setProductsLoaded(true);
      })
      .catch((err) => {
        if (cancelled) return;
        setProducts([]);
        setProductsError(
          err instanceof Error ? err.message : "Gagal memuat riwayat pembelian.",
        );
      })
      .finally(() => {
        if (!cancelled) setProductsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [open, productsLoaded]);

  useEffect(() => {
    if (!open) {
      stopPreview();
      setStep("pick");
      setSelecting(false);
      setVideoError(null);
      setFormError(null);
      setUploadStage(null);
      setUploadProgress(0);
      setSubmittedPost(null);
    }
  }, [open]);

  useEffect(() => {
    return () => {
      if (selectedVideo?.previewUrl) URL.revokeObjectURL(selectedVideo.previewUrl);
      if (selectedVideo?.thumbnailUrl) URL.revokeObjectURL(selectedVideo.thumbnailUrl);
    };
  }, [selectedVideo]);

  if (!open) return null;

  function closeFlow() {
    if (uploadStage) return;
    onClose();
  }

  function resetVideo(next?: SelectedVideo) {
    stopPreview();
    if (selectedVideo?.previewUrl) URL.revokeObjectURL(selectedVideo.previewUrl);
    if (selectedVideo?.thumbnailUrl) URL.revokeObjectURL(selectedVideo.thumbnailUrl);
    setSelectedVideo(next ?? null);
  }

  async function handleVideoPick(file: File | null) {
    if (!file) return;
    const pickToken = pickTokenRef.current + 1;
    pickTokenRef.current = pickToken;
    setSelecting(true);
    setVideoError(null);
    setFormError(null);

    try {
      validatePickedVideoFile(file);
      debugFeedVideo("pick:start", getVideoDebugBase(file));

      const localFile = await copyVideoToLocalFile(file);
      debugFeedVideo("pick:local-copy-ready", {
        ...getVideoDebugBase(file),
        localCachePath: localFile.name,
        localSize: localFile.size,
      });

      const metadata = await readVideoMetadata(localFile);
      debugFeedVideo("metadata:loaded", {
        ...getVideoDebugBase(localFile),
        durationSec: metadata.durationSec,
        width: metadata.width,
        height: metadata.height,
      });

      const fallbackThumbnailBlob = await createFallbackVideoThumbnail(metadata);
      const previewUrl = URL.createObjectURL(localFile);
      const thumbnailUrl = URL.createObjectURL(fallbackThumbnailBlob);
      const duration = Math.max(0, metadata.durationSec);
      const nextStart = 0;
      const nextEnd = Math.min(duration, MAX_VIDEO_DURATION);

      resetVideo({
        file: localFile,
        previewUrl,
        thumbnailBlob: fallbackThumbnailBlob,
        thumbnailUrl,
        thumbnailIsFallback: true,
        metadata,
      });
      setTrimStart(nextStart);
      setTrimEnd(nextEnd);

      if (duration < MIN_VIDEO_DURATION) {
        setVideoError(`Video terlalu pendek. Upload video minimal ${MIN_VIDEO_DURATION} detik.`);
        void hapticWarning();
      } else if (duration > MAX_VIDEO_DURATION) {
        setVideoError(`Video maksimal ${MAX_VIDEO_DURATION} detik. Potong video terlebih dahulu sebelum lanjut.`);
        void hapticTap();
        void generateThumbnailBestEffort(localFile, metadata, pickToken);
      } else {
        void hapticTap();
        void generateThumbnailBestEffort(localFile, metadata, pickToken);
      }
    } catch (err) {
      debugFeedVideo("pick:error", {
        ...getVideoDebugBase(file),
        error: serializeError(err),
      });
      setVideoError(getFriendlyVideoPickError(err));
      void hapticWarning();
    } finally {
      setSelecting(false);
      if (galleryInputRef.current) galleryInputRef.current.value = "";
      if (cameraInputRef.current) cameraInputRef.current.value = "";
    }
  }

  async function generateThumbnailBestEffort(
    file: File,
    metadata: VideoMetadata,
    pickToken: number,
  ) {
    const startedAt = performance.now();
    debugFeedVideo("thumbnail:start", {
      ...getVideoDebugBase(file),
      targetTimeSec: Math.min(1, Math.max(0.5, metadata.durationSec / 2)),
    });

    try {
      const thumbnailBlob = await extractVideoThumbnail(file, {
        targetTimeSec: Math.min(1, Math.max(0.5, metadata.durationSec / 2)),
        maxWidth: 480,
        timeoutMs: 30000,
      });
      const thumbnailUrl = URL.createObjectURL(thumbnailBlob);
      const elapsedMs = Math.round(performance.now() - startedAt);
      debugFeedVideo("thumbnail:success", {
        ...getVideoDebugBase(file),
        elapsedMs,
        thumbnailSize: thumbnailBlob.size,
        usedFallback: false,
      });

      setSelectedVideo((current) => {
        if (!current || pickTokenRef.current !== pickToken || current.file !== file) {
          URL.revokeObjectURL(thumbnailUrl);
          return current;
        }
        URL.revokeObjectURL(current.thumbnailUrl);
        return {
          ...current,
          thumbnailBlob,
          thumbnailUrl,
          thumbnailIsFallback: false,
        };
      });
    } catch (err) {
      debugFeedVideo("thumbnail:fallback", {
        ...getVideoDebugBase(file),
        elapsedMs: Math.round(performance.now() - startedAt),
        error: serializeError(err),
        usedFallback: true,
      });
      setVideoError((current) => current ?? "Video berhasil dipilih, tetapi preview belum bisa dibuat.");
    }
  }

  function goNextFromPicker() {
    if (!selectedVideo || selectedTooShort) return;
    if (selectedVideo.metadata.durationSec > MAX_VIDEO_DURATION) {
      setStep("trim");
    } else {
      setStep("detail");
    }
  }

  function updateTrimStart(value: number) {
    if (!selectedVideo) return;
    const duration = selectedVideo.metadata.durationSec;
    const nextStart = Math.max(0, Math.min(value, duration - 0.5));
    const nextEnd = Math.max(nextStart + 0.5, trimEnd);
    setTrimStart(nextStart);
    setTrimEnd(Math.min(duration, nextEnd));
  }

  function updateTrimEnd(value: number) {
    if (!selectedVideo) return;
    const duration = selectedVideo.metadata.durationSec;
    const nextEnd = Math.max(0.5, Math.min(value, duration));
    setTrimEnd(Math.max(nextEnd, trimStart + 0.5));
  }

  function togglePreview() {
    const video = previewVideoRef.current;
    if (!video) return;
    if (video.paused) {
      void video.play();
      setIsPlaying(true);
    } else {
      video.pause();
      setIsPlaying(false);
    }
  }

  function stopPreview() {
    const video = previewVideoRef.current;
    if (video) video.pause();
    setIsPlaying(false);
  }

  function updateCaption(value: string) {
    setCaption(value.slice(0, MAX_CAPTION_LENGTH));
    setFormError(null);
  }

  function toggleProduct(productId: string) {
    setFormError(null);
    setSelectedProductIds((current) => {
      if (current.includes(productId)) {
        return current.filter((id) => id !== productId);
      }
      if (current.length >= MAX_PINNED_PRODUCTS) {
        void hapticWarning();
        setFormError(`Maksimal ${MAX_PINNED_PRODUCTS} produk yang bisa di-pin.`);
        return current;
      }
      void hapticTap();
      return [...current, productId];
    });
  }

  function submitPost() {
    if (!selectedVideo || !canPost) {
      // Surface why the action was a no-op — without this the user sees
      // "loading dulu" haptic on the button but nothing happens.
      natToast(
        !selectedVideo
          ? "Belum ada video terpilih."
          : "Durasi video belum valid (1-45 detik).",
        { kind: "warn" },
      );
      void hapticWarning();
      return;
    }
    if (feedUpload.state.active && feedUpload.state.stage !== "done" && feedUpload.state.stage !== "error") {
      // Another upload is still running in the background — let the user
      // know rather than silently queuing a second one.
      setFormError("Upload sebelumnya masih berjalan. Tunggu sebentar ya.");
      natToast("Upload sebelumnya masih berjalan. Tunggu sebentar ya.", {
        kind: "warn",
      });
      void hapticWarning();
      return;
    }
    setFormError(null);
    void hapticSuccess();

    // Hand the heavy work off to the background provider so the sheet can
    // dismiss immediately. The floating <FeedUploadToast> renders progress
    // and a final "Postingan terkirim" pill while the user keeps browsing.
    feedUpload.start({
      videoFile: selectedVideo.file,
      thumbnailBlob: selectedVideo.thumbnailBlob,
      trimStartSec: trimStart,
      trimDurationSec: finalDuration,
      videoWidth: selectedVideo.metadata.width,
      videoHeight: selectedVideo.metadata.height,
      caption,
      petType,
      petName,
      selectedProductIds,
    });

    // Belt-and-suspenders: also drop a regular toast so the user gets a
    // visible "your video is uploading" signal even if the floating
    // <FeedUploadToast> ends up behind another fixed element or fails to
    // mount. natToast lives in <ToastProvider> at the body root.
    natToast("Mengupload videomu di latar belakang…", { kind: "default" });

    resetAndClose();
  }

  function resetAndClose() {
    resetVideo();
    setCaption("");
    setPetType(null);
    setPetName("");
    setSelectedProductIds([]);
    setProductPickerOpen(false);
    setSubmittedPost(null);
    setStep("pick");
    onClose();
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={getStepTitle(step)}
      data-no-swipe-back="true"
      className="fixed inset-0 z-[2000] bg-black text-white"
    >
      {step === "pick" && (
        <PickVideoStep
          galleryInputRef={galleryInputRef}
          cameraInputRef={cameraInputRef}
          selectedVideo={selectedVideo}
          selecting={selecting}
          videoError={videoError}
          canContinue={selectedCanContinue}
          onClose={closeFlow}
          onPick={handleVideoPick}
          onNext={goNextFromPicker}
        />
      )}
      {step === "trim" && selectedVideo && (
        <TrimVideoStep
          selectedVideo={selectedVideo}
          videoRef={previewVideoRef}
          isPlaying={isPlaying}
          trimStart={trimStart}
          trimEnd={trimEnd}
          finalDuration={finalDuration}
          isValid={hasValidFinalDuration}
          onBack={() => {
            stopPreview();
            setStep("pick");
          }}
          onNext={() => {
            stopPreview();
            if (hasValidFinalDuration) setStep("detail");
          }}
          onTogglePlay={togglePreview}
          onTrimStartChange={updateTrimStart}
          onTrimEndChange={updateTrimEnd}
        />
      )}
      {step === "detail" && selectedVideo && (
        <DetailPostStep
          selectedVideo={selectedVideo}
          caption={caption}
          petType={petType}
          petName={petName}
          selectedProducts={selectedProducts}
          selectedProductIds={selectedProductIds}
          products={products}
          productsLoading={productsLoading}
          productsError={productsError}
          productPickerOpen={productPickerOpen}
          finalDuration={finalDuration}
          canPost={canPost}
          formError={formError}
          onBack={() => setStep(selectedNeedsTrim ? "trim" : "pick")}
          onChangeVideo={() => setStep("pick")}
          onCaptionChange={updateCaption}
          onPetTypeChange={setPetType}
          onPetNameChange={(value) => setPetName(value.slice(0, 80))}
          onToggleProductPicker={() => {
            setProductPickerOpen((value) => !value);
            void hapticTap();
          }}
          onToggleProduct={toggleProduct}
          onSubmit={submitPost}
        />
      )}
      {/* Inline uploading overlay removed — background uploads are handled by
          <FeedUploadProvider> + the floating <FeedUploadToast> so the sheet
          can dismiss as soon as the user taps "Posting". */}
      {step === "success" && selectedVideo && (
        <SuccessStep
          selectedVideo={selectedVideo}
          finalDuration={finalDuration}
          status={submittedPost?.status ?? "PENDING_REVIEW"}
          onViewStatus={() => setStep("status")}
          onBackToFeed={resetAndClose}
        />
      )}
      {step === "status" && selectedVideo && (
        <StatusStep
          selectedVideo={selectedVideo}
          caption={caption}
          finalDuration={finalDuration}
          onBack={() => setStep("success")}
          onBackToFeed={resetAndClose}
        />
      )}
    </div>
  );
}

function PickVideoStep({
  galleryInputRef,
  cameraInputRef,
  selectedVideo,
  selecting,
  videoError,
  canContinue,
  onClose,
  onPick,
  onNext,
}: {
  galleryInputRef: RefObject<HTMLInputElement | null>;
  cameraInputRef: RefObject<HTMLInputElement | null>;
  selectedVideo: SelectedVideo | null;
  selecting: boolean;
  videoError: string | null;
  canContinue: boolean;
  onClose: () => void;
  onPick: (file: File | null) => void;
  onNext: () => void;
}) {
  // iOS 26 WKWebView crash dengan <input capture="environment"> — code path
  // WebKit terminate process sebelum WKFileUploadPanel render permission
  // prompt. Workaround: di iOS drop capture attribute → iOS tampilkan native
  // file picker dengan opsi "Take Photo or Video" + "Photo Library". 1 extra
  // tap di iOS tapi tidak crash. Android tetap pakai capture untuk direct-
  // launch kamera ke video recording mode (no bug di sana).
  const onIOS = isIOS();
  const cameraCaption = onIOS ? "Pilih atau rekam video" : "Rekam video baru";
  return (
    <div className="flex h-full flex-col bg-black">
      <DarkHeader
        title="Pilih Video"
        leftIcon={<FiX className="h-5 w-5" />}
        leftLabel="Tutup"
        onLeft={onClose}
        rightLabel="Next"
        rightDisabled={!canContinue || selecting}
        onRight={onNext}
      />

      <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-[calc(24px+env(safe-area-inset-bottom))]">
        <div className="mx-auto max-w-2xl">
          {/* Pakai <label> wrapping <input> alih-alih <button> + programmatic
              .click(). Di iOS WKWebView 17+, user-gesture context bisa lost
              antara React onClick handler fires dan ref.current.click() dipanggil
              (microtask boundary) → WKFileUploadPanel reject + crash, terutama
              untuk input dengan capture="environment" yang memicu
              UIImagePickerController. Label→input native association preserve
              user-gesture end-to-end via DOM event propagation. */}
          <div className="grid grid-cols-2 gap-3 pt-4">
            <label className="block cursor-pointer rounded-3xl border border-white/10 bg-white/10 p-4 text-left transition active:scale-[0.98]">
              <FiImage className="h-6 w-6 text-natalo-300" />
              <p className="mt-3 text-sm font-black">Galeri</p>
              <p className="mt-1 text-xs font-semibold text-white/55">
                Pilih video dari perangkat
              </p>
              <input
                ref={galleryInputRef}
                type="file"
                accept={ACCEPT_VIDEO_GALLERY}
                className="hidden"
                onChange={(event) => onPick(event.target.files?.[0] ?? null)}
              />
            </label>
            <label className="block cursor-pointer rounded-3xl border border-white/10 bg-white/10 p-4 text-left transition active:scale-[0.98]">
              <FiCamera className="h-6 w-6 text-natalo-300" />
              <p className="mt-3 text-sm font-black">Kamera</p>
              <p className="mt-1 text-xs font-semibold text-white/55">
                {cameraCaption}
              </p>
              {onIOS ? (
                <input
                  ref={cameraInputRef}
                  type="file"
                  accept={ACCEPT_VIDEO_CAMERA}
                  className="hidden"
                  onChange={(event) => onPick(event.target.files?.[0] ?? null)}
                />
              ) : (
                <input
                  ref={cameraInputRef}
                  type="file"
                  accept={ACCEPT_VIDEO_CAMERA}
                  capture="environment"
                  className="hidden"
                  onChange={(event) => onPick(event.target.files?.[0] ?? null)}
                />
              )}
            </label>
          </div>

          <div className="mt-4 inline-flex items-center gap-2 rounded-full bg-natalo-600/20 px-3 py-2 text-xs font-black text-natalo-100 ring-1 ring-natalo-400/30">
            <FiInfo className="h-4 w-4" />
            Pilih video berdurasi {DURATION_RANGE_LABEL}
          </div>

          {selecting && (
            <div className="mt-4 rounded-3xl border border-white/10 bg-white/10 p-4 text-sm font-bold text-white/70">
              Menyiapkan video...
            </div>
          )}

          {videoError && (
            <div className="mt-4 flex items-start gap-2 rounded-3xl border border-amber-400/30 bg-amber-400/10 p-4 text-sm font-bold leading-relaxed text-amber-100">
              <FiAlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{videoError}</span>
            </div>
          )}

          <div className="mt-5 flex items-center justify-between">
            <h2 className="text-sm font-black">Terbaru</h2>
            <span className="text-xs font-bold text-white/45">Video terbaru tampil dulu</span>
          </div>

          <div className="mt-3 grid grid-cols-3 gap-2">
            {selectedVideo ? (
              <button
                type="button"
                onClick={() => void hapticTap()}
                className="relative aspect-[3/4] overflow-hidden rounded-2xl border-2 border-natalo-500 bg-white/10 text-left shadow-[0_0_0_1px_rgba(255,255,255,0.08)]"
              >
                <img
                  src={selectedVideo.thumbnailUrl}
                  alt=""
                  className="h-full w-full object-cover"
                />
                <span className="absolute bottom-1.5 right-1.5 rounded-full bg-black/70 px-2 py-1 text-[11px] font-black text-white">
                  {formatDuration(selectedVideo.metadata.durationSec)}
                </span>
                <span className="absolute right-1.5 top-1.5 grid h-7 w-7 place-items-center rounded-full bg-natalo-600 text-white">
                  <FiCheck className="h-4 w-4" />
                </span>
              </button>
            ) : (
              <button
                type="button"
                onClick={() => galleryInputRef.current?.click()}
                className="flex aspect-[3/4] flex-col items-center justify-center rounded-2xl border border-dashed border-white/20 bg-white/[0.06] text-center text-white/55"
              >
                <FiFilm className="h-7 w-7" />
                <span className="mt-2 px-2 text-xs font-black">Pilih video</span>
              </button>
            )}
            {Array.from({ length: selectedVideo ? 5 : 8 }).map((_, index) => (
              <div
                key={index}
                className="aspect-[3/4] rounded-2xl border border-white/5 bg-white/[0.04]"
                aria-hidden="true"
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function TrimVideoStep({
  selectedVideo,
  videoRef,
  isPlaying,
  trimStart,
  trimEnd,
  finalDuration,
  isValid,
  onBack,
  onNext,
  onTogglePlay,
  onTrimStartChange,
  onTrimEndChange,
}: {
  selectedVideo: SelectedVideo;
  videoRef: RefObject<HTMLVideoElement | null>;
  isPlaying: boolean;
  trimStart: number;
  trimEnd: number;
  finalDuration: number;
  isValid: boolean;
  onBack: () => void;
  onNext: () => void;
  onTogglePlay: () => void;
  onTrimStartChange: (value: number) => void;
  onTrimEndChange: (value: number) => void;
}) {
  const duration = selectedVideo.metadata.durationSec;
  const invalidText =
    finalDuration < MIN_VIDEO_DURATION
      ? `Video terlalu pendek. Upload minimal ${MIN_VIDEO_DURATION} detik.`
      : `Video terlalu panjang. Maksimal ${MAX_VIDEO_DURATION} detik.`;

  return (
    <div className="flex h-full flex-col bg-black">
      <DarkHeader
        title="Trim Video"
        leftIcon={<FiArrowLeft className="h-5 w-5" />}
        leftLabel="Kembali"
        onLeft={onBack}
        rightLabel="Next"
        rightDisabled={!isValid}
        onRight={onNext}
      />
      <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-[calc(24px+env(safe-area-inset-bottom))]">
        <div className="mx-auto max-w-2xl pt-4">
          <div className="relative overflow-hidden rounded-[28px] bg-white/10">
            <video
              ref={videoRef}
              src={selectedVideo.previewUrl}
              className="aspect-[9/14] w-full object-cover"
              playsInline
              muted
              onEnded={() => {
                const video = videoRef.current;
                if (video) video.currentTime = trimStart;
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
              {formatDuration(finalDuration)} / {formatDuration(duration)}
            </span>
          </div>

          <div className="mt-5 rounded-3xl border border-white/10 bg-white/10 p-4">
            <div className="mb-3 flex items-center justify-between text-xs font-black text-white/65">
              <span>{formatDuration(trimStart)}</span>
              <span>{formatDuration(trimEnd)}</span>
            </div>
            <div className="rounded-2xl border border-natalo-400/70 bg-black/50 p-3">
              <div className="h-14 overflow-hidden rounded-xl bg-[linear-gradient(90deg,rgba(30,95,191,.55),rgba(255,255,255,.14),rgba(30,95,191,.55))]" />
              <label className="mt-4 block text-xs font-black text-white/60">
                Mulai trim
                <input
                  type="range"
                  min={0}
                  max={Math.max(0, duration - 0.5)}
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
                  min={0.5}
                  max={duration}
                  step={0.1}
                  value={trimEnd}
                  onChange={(event) => onTrimEndChange(Number(event.target.value))}
                  className="mt-2 w-full accent-natalo-500"
                />
              </label>
            </div>
          </div>

          <div className="mt-4 rounded-3xl bg-natalo-600/25 p-4 text-sm font-black text-natalo-50 ring-1 ring-natalo-400/30">
            Durasi final harus {DURATION_RANGE_LABEL}
          </div>
          <div
            className={`mt-3 flex items-center gap-3 rounded-3xl p-4 text-sm font-black ${
              isValid
                ? "bg-emerald-500/15 text-emerald-200"
                : "bg-amber-400/10 text-amber-100"
            }`}
          >
            {isValid ? (
              <span className="grid h-9 w-9 place-items-center rounded-full bg-emerald-500 text-white">
                <FiCheck className="h-5 w-5" />
              </span>
            ) : (
              <FiAlertCircle className="h-5 w-5 shrink-0" />
            )}
            <span>{isValid ? "Durasi valid" : invalidText}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

function DetailPostStep({
  selectedVideo,
  caption,
  petType,
  petName,
  selectedProducts,
  selectedProductIds,
  products,
  productsLoading,
  productsError,
  productPickerOpen,
  finalDuration,
  canPost,
  formError,
  onBack,
  onChangeVideo,
  onCaptionChange,
  onPetTypeChange,
  onPetNameChange,
  onToggleProductPicker,
  onToggleProduct,
  onSubmit,
}: {
  selectedVideo: SelectedVideo;
  caption: string;
  petType: string | null;
  petName: string;
  selectedProducts: PinnableProduct[];
  selectedProductIds: string[];
  products: PinnableProduct[];
  productsLoading: boolean;
  productsError: string | null;
  productPickerOpen: boolean;
  finalDuration: number;
  canPost: boolean;
  formError: string | null;
  onBack: () => void;
  onChangeVideo: () => void;
  onCaptionChange: (value: string) => void;
  onPetTypeChange: (value: string | null) => void;
  onPetNameChange: (value: string) => void;
  onToggleProductPicker: () => void;
  onToggleProduct: (productId: string) => void;
  onSubmit: () => void;
}) {
  return (
    <div className="flex h-full flex-col bg-zinc-50 text-zinc-950">
      <LightHeader
        title="Detail Postingan"
        leftIcon={<FiArrowLeft className="h-5 w-5" />}
        leftLabel="Kembali"
        onLeft={onBack}
        rightLabel="Posting"
        rightDisabled={!canPost}
        onRight={onSubmit}
      />
      <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-[calc(24px+env(safe-area-inset-bottom))]">
        <div className="mx-auto max-w-2xl space-y-4 pt-4">
          {formError && (
            <div className="flex items-start gap-2 rounded-3xl border border-red-100 bg-red-50 p-3 text-xs font-bold leading-relaxed text-red-700">
              <FiAlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{formError}</span>
            </div>
          )}

          <section className="grid grid-cols-[minmax(0,1fr)_auto] gap-3 rounded-3xl border border-zinc-100 bg-white p-3 shadow-sm">
            <div className="relative aspect-[4/3] overflow-hidden rounded-2xl bg-zinc-100">
              <img
                src={selectedVideo.thumbnailUrl}
                alt=""
                className="h-full w-full object-cover"
              />
              <span className="absolute bottom-2 left-2 rounded-full bg-black/70 px-2 py-1 text-xs font-black text-white">
                {formatDuration(finalDuration)}
              </span>
              <span className="absolute inset-0 m-auto grid h-10 w-10 place-items-center rounded-full bg-black/45 text-white">
                <FiPlay className="h-4 w-4" />
              </span>
            </div>
            <div className="flex w-28 flex-col justify-center">
              <p className="text-sm font-black text-zinc-950">{formatDuration(finalDuration)}</p>
              <p className="mt-1 text-xs font-bold leading-relaxed text-zinc-500">
                Video siap diupload
              </p>
              <button
                type="button"
                onClick={onChangeVideo}
                className="mt-3 rounded-xl border border-natalo-500 px-3 py-2 text-xs font-black text-natalo-600"
              >
                Ganti Video
              </button>
            </div>
          </section>

          <section className="rounded-3xl border border-zinc-100 bg-white p-4 shadow-sm">
            <div className="flex items-center justify-between gap-3">
              <h2 className="text-sm font-black text-zinc-950">✍️ Caption</h2>
              <span className="text-xs font-extrabold text-zinc-400">
                {caption.length} / {MAX_CAPTION_LENGTH}
              </span>
            </div>
            <textarea
              value={caption}
              onChange={(event) => onCaptionChange(event.target.value)}
              maxLength={MAX_CAPTION_LENGTH}
              rows={4}
              placeholder="Ceritakan pengalamanmu bersama hewan peliharaan & produk Natalo..."
              className="mt-3 w-full resize-none rounded-2xl border border-zinc-200 bg-zinc-50 px-3 py-3 text-sm font-semibold leading-relaxed text-zinc-900 outline-none placeholder:text-zinc-400 focus:border-natalo-500 focus:bg-white"
            />
          </section>

          <section className="rounded-3xl border border-zinc-100 bg-white p-4 shadow-sm">
            <h2 className="text-sm font-black text-zinc-950">🛒 Pin Produk yang Dipakai</h2>
            <p className="mt-1 text-xs font-semibold leading-relaxed text-zinc-500">
              Maksimal 3 produk · Hanya dari riwayat pembelianmu yang sudah diterima
            </p>

            {selectedProducts.length > 0 && (
              <div className="mt-3 flex flex-wrap gap-2">
                {selectedProducts.map((product) => (
                  <button
                    key={product.productId}
                    type="button"
                    onClick={() => onToggleProduct(product.productId)}
                    className="inline-flex max-w-full items-center gap-1.5 rounded-full border border-natalo-200 bg-natalo-50 px-3 py-1.5 text-left text-[11px] font-extrabold text-natalo-700"
                  >
                    <span className="truncate">{product.name}</span>
                    <FiX className="h-3.5 w-3.5 shrink-0" />
                  </button>
                ))}
              </div>
            )}

            <button
              type="button"
              onClick={onToggleProductPicker}
              className="mt-3 flex w-full items-center justify-center gap-2 rounded-2xl border border-dashed border-natalo-400 bg-natalo-50 px-3 py-3 text-sm font-black text-natalo-700 transition active:scale-[0.99]"
            >
              <FiPlus className="h-4 w-4" />
              Pilih Produk dari Riwayat Pembelian
            </button>

            {productPickerOpen && (
              <ProductPickerPanel
                products={products}
                selectedProductIds={selectedProductIds}
                loading={productsLoading}
                error={productsError}
                onToggleProduct={onToggleProduct}
              />
            )}
          </section>

          <section className="rounded-3xl border border-zinc-100 bg-white p-4 shadow-sm">
            <h2 className="text-sm font-black text-zinc-950">🐾 Info Peliharaan</h2>
            <p className="mt-1 text-xs font-semibold text-zinc-500">
              Bantu viewer kenal lebih dekat
            </p>
            <div className="mt-3 flex flex-wrap gap-2">
              {PET_TYPES.map((type) => {
                const selected = petType === type;
                return (
                  <button
                    key={type}
                    type="button"
                    onClick={() => {
                      onPetTypeChange(selected ? null : type);
                      void hapticTap();
                    }}
                    className={`rounded-xl border px-3 py-2 text-xs font-black transition active:scale-95 ${
                      selected
                        ? "border-natalo-500 bg-natalo-50 text-natalo-700"
                        : "border-zinc-200 bg-zinc-100 text-zinc-600"
                    }`}
                  >
                    {type}
                  </button>
                );
              })}
            </div>
            <input
              type="text"
              value={petName}
              onChange={(event) => onPetNameChange(event.target.value)}
              placeholder="Nama peliharaan & jenis ras (cth: Miko · Persian)"
              className="mt-3 w-full rounded-2xl border border-zinc-200 bg-zinc-50 px-3 py-3 text-sm font-semibold text-zinc-900 outline-none placeholder:text-zinc-400 focus:border-natalo-500 focus:bg-white"
            />
          </section>

          <div className="flex items-start gap-2 rounded-3xl border border-amber-200 bg-amber-50 p-4 text-xs font-bold leading-relaxed text-amber-900">
            <FiInfo className="mt-0.5 h-4 w-4 shrink-0" />
            <p>
              Postingan akan ditinjau admin sebelum tayang di Feed (max. 1×24 jam).
              Pastikan konten sesuai pedoman komunitas Natalo.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

function SuccessStep({
  selectedVideo,
  finalDuration,
  status,
  onViewStatus,
  onBackToFeed,
}: {
  selectedVideo: SelectedVideo;
  finalDuration: number;
  status: string;
  onViewStatus: () => void;
  onBackToFeed: () => void;
}) {
  return (
    <div className="flex h-full flex-col bg-white px-5 pb-[calc(24px+env(safe-area-inset-bottom))] pt-[calc(54px+env(safe-area-inset-top))] text-center text-zinc-950">
      <div className="mx-auto flex min-h-0 w-full max-w-md flex-1 flex-col justify-center">
        <FeedUploadSuccessLottie />
        <h1 className="mt-3 text-xl font-black">Postingan Berhasil Dikirim</h1>
        <p className="mx-auto mt-2 max-w-xs text-sm font-semibold leading-relaxed text-zinc-500">
          Video kamu sudah masuk antrean review admin.
        </p>

        <div className="mt-6 flex items-center gap-3 rounded-3xl border border-zinc-100 bg-white p-3 text-left shadow-sm">
          <img
            src={selectedVideo.thumbnailUrl}
            alt=""
            className="h-24 w-24 rounded-2xl object-cover"
          />
          <div className="min-w-0 flex-1">
            <p className="text-sm font-black text-zinc-950">Video Feed</p>
            <p className="mt-1 text-sm font-bold text-zinc-500">{formatDuration(finalDuration)}</p>
            <span className="mt-3 inline-flex rounded-full bg-amber-100 px-3 py-1 text-xs font-black text-amber-700">
              {status.toLowerCase() === "pending_review" ||
              status.toUpperCase() === "PENDING_REVIEW"
                ? "pending_review"
                : status}
            </span>
          </div>
        </div>

        <div className="mt-4 space-y-3 rounded-3xl border border-zinc-100 bg-white p-4 text-left text-sm font-bold shadow-sm">
          <div className="flex items-center justify-between gap-3">
            <span className="inline-flex items-center gap-2 text-zinc-600">
              <FiClock className="h-4 w-4" />
              Estimasi review:
            </span>
            <span>max. 1×24 jam</span>
          </div>
          <div className="flex items-center justify-between gap-3">
            <span className="inline-flex items-center gap-2 text-zinc-600">
              <FiPackage className="h-4 w-4" />
              Status awal:
            </span>
            <span className="text-amber-600">Menunggu Review</span>
          </div>
        </div>

        <div className="mt-6 space-y-3">
          <button
            type="button"
            onClick={onViewStatus}
            className="w-full rounded-2xl bg-natalo-600 py-3.5 text-sm font-black text-white"
          >
            Lihat Status
          </button>
          <button
            type="button"
            onClick={onBackToFeed}
            className="w-full rounded-2xl bg-zinc-100 py-3.5 text-sm font-black text-zinc-950"
          >
            Kembali ke Feed
          </button>
        </div>
      </div>
    </div>
  );
}

function StatusStep({
  selectedVideo,
  caption,
  finalDuration,
  onBack,
  onBackToFeed,
}: {
  selectedVideo: SelectedVideo;
  caption: string;
  finalDuration: number;
  onBack: () => void;
  onBackToFeed: () => void;
}) {
  return (
    <div className="flex h-full flex-col bg-zinc-50 text-zinc-950">
      <LightHeader
        title="Video Saya"
        leftIcon={<FiArrowLeft className="h-5 w-5" />}
        leftLabel="Kembali"
        onLeft={onBack}
      />
      <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-[calc(24px+env(safe-area-inset-bottom))]">
        <div className="mx-auto max-w-2xl space-y-4 pt-4">
          <div className="flex gap-3 rounded-3xl border border-zinc-100 bg-white p-4 shadow-sm">
            <img
              src={selectedVideo.thumbnailUrl}
              alt=""
              className="h-36 w-28 rounded-2xl object-cover"
            />
            <div className="min-w-0 flex-1">
              <h1 className="text-sm font-black leading-snug">
                {caption.trim() || "Pengalaman bersama Natalo"}
              </h1>
              <p className="mt-2 text-xs font-bold text-zinc-500">Baru saja</p>
              <span className="mt-3 inline-flex rounded-full bg-amber-100 px-3 py-1.5 text-xs font-black text-amber-700">
                Menunggu Review
              </span>
              <p className="mt-4 text-xs font-semibold leading-relaxed text-zinc-500">
                Akan tayang di Feed setelah disetujui admin.
              </p>
            </div>
          </div>

          <div className="rounded-3xl bg-natalo-50 p-4 text-sm font-semibold leading-relaxed text-zinc-800">
            <div className="flex gap-3">
              <FiInfo className="mt-0.5 h-5 w-5 shrink-0 text-natalo-600" />
              <ul className="space-y-2">
                <li>Durasi video valid {DURATION_RANGE_LABEL} ({formatDuration(finalDuration)})</li>
                <li>Review admin maksimal 1×24 jam</li>
                <li>Notifikasi akan dikirim saat status berubah</li>
              </ul>
            </div>
          </div>

          <button
            type="button"
            onClick={onBackToFeed}
            className="fixed inset-x-4 bottom-[calc(18px+env(safe-area-inset-bottom))] mx-auto max-w-2xl rounded-2xl bg-natalo-600 py-3.5 text-sm font-black text-white shadow-lg"
          >
            Kembali ke Feed
          </button>
        </div>
      </div>
    </div>
  );
}

function ProductPickerPanel({
  products,
  selectedProductIds,
  loading,
  error,
  onToggleProduct,
}: {
  products: PinnableProduct[];
  selectedProductIds: string[];
  loading: boolean;
  error: string | null;
  onToggleProduct: (productId: string) => void;
}) {
  if (loading) {
    return (
      <p className="mt-3 rounded-2xl bg-zinc-50 p-4 text-center text-xs font-bold text-zinc-400">
        Memuat riwayat pembelian...
      </p>
    );
  }

  if (error) {
    return (
      <p className="mt-3 rounded-2xl bg-red-50 p-4 text-center text-xs font-bold leading-relaxed text-red-700">
        {error}
      </p>
    );
  }

  if (products.length === 0) {
    return (
      <div className="mt-3 rounded-2xl bg-zinc-50 p-4 text-center">
        <p className="text-sm font-black text-zinc-700">
          Belum ada produk yang bisa dipilih dari riwayat pembelian.
        </p>
      </div>
    );
  }

  return (
    <div className="mt-3 max-h-72 space-y-2 overflow-y-auto pr-1">
      {products.map((product) => {
        const selected = selectedProductIds.includes(product.productId);
        return (
          <button
            key={`${product.productId}-${product.orderNumber}`}
            type="button"
            onClick={() => onToggleProduct(product.productId)}
            className={`flex w-full items-center gap-3 rounded-2xl border p-3 text-left transition active:scale-[0.99] ${
              selected
                ? "border-natalo-500 bg-natalo-50"
                : "border-zinc-100 bg-white"
            }`}
          >
            <div className="grid h-14 w-14 shrink-0 place-items-center overflow-hidden rounded-2xl bg-zinc-100 text-natalo-600">
              {product.imageUrl ? (
                <img
                  src={product.imageUrl}
                  alt=""
                  className="h-full w-full object-cover"
                />
              ) : (
                <FiPackage className="h-5 w-5" />
              )}
            </div>
            <div className="min-w-0 flex-1">
              <p className="line-clamp-2 text-xs font-black leading-snug text-zinc-900">
                {product.name}
              </p>
              <p className="mt-1 text-xs font-black text-natalo-600">
                {formatRupiah(product.price)}
              </p>
              <p className="mt-0.5 text-[11px] font-semibold text-zinc-500">
                Dibeli {formatDate(product.purchasedAt)}
              </p>
            </div>
            <span
              className={`grid h-7 w-7 shrink-0 place-items-center rounded-full border ${
                selected
                  ? "border-natalo-600 bg-natalo-600 text-white"
                  : "border-zinc-200 bg-white text-transparent"
              }`}
            >
              <FiCheck className="h-4 w-4" />
            </span>
          </button>
        );
      })}
    </div>
  );
}

function UploadingStep({ stage, progress }: { stage: UploadStage; progress: number }) {
  const label =
    stage === "compressing"
      ? "Memproses video..."
      : stage === "uploading-video"
        ? "Mengunggah video..."
        : stage === "uploading-thumbnail"
          ? "Mengunggah thumbnail..."
          : "Menyimpan postingan...";

  return (
    <div className="w-full max-w-xs rounded-3xl bg-white p-5 text-center text-zinc-950 shadow-xl">
      <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-natalo-50 text-natalo-600">
        <FiUploadCloud className="h-7 w-7" />
      </div>
      <p className="mt-4 text-sm font-black">{label}</p>
      <div className="mt-4 h-2 overflow-hidden rounded-full bg-zinc-100">
        <div
          className="h-full rounded-full bg-natalo-600 transition-[width]"
          style={{ width: `${stage === "compressing" ? progress : 100}%` }}
        />
      </div>
      <p className="mt-2 text-xs font-bold text-zinc-500">
        {stage === "compressing" ? `${progress}%` : "Mohon tunggu sebentar"}
      </p>
    </div>
  );
}

function DarkHeader({
  title,
  leftIcon,
  leftLabel,
  onLeft,
  rightLabel,
  rightDisabled,
  onRight,
}: {
  title: string;
  leftIcon: ReactNode;
  leftLabel: string;
  onLeft: () => void;
  rightLabel?: string;
  rightDisabled?: boolean;
  onRight?: () => void;
}) {
  return (
    <header className="grid h-[calc(56px+env(safe-area-inset-top))] shrink-0 grid-cols-[64px_1fr_64px] items-end px-2 pb-2 pt-[env(safe-area-inset-top)]">
      <button
        type="button"
        onClick={onLeft}
        aria-label={leftLabel}
        className="grid h-11 w-11 place-items-center rounded-full text-white/90"
      >
        {leftIcon}
      </button>
      <h1 className="pb-3 text-center text-sm font-black text-white">{title}</h1>
      {rightLabel ? (
        <button
          type="button"
          onClick={onRight}
          disabled={rightDisabled}
          className="justify-self-end rounded-full px-2 py-3 text-sm font-black text-natalo-400 disabled:text-white/35"
        >
          {rightLabel}
        </button>
      ) : (
        <span />
      )}
    </header>
  );
}

function LightHeader({
  title,
  leftIcon,
  leftLabel,
  onLeft,
  rightLabel,
  rightDisabled,
  onRight,
}: {
  title: string;
  leftIcon: ReactNode;
  leftLabel: string;
  onLeft: () => void;
  rightLabel?: string;
  rightDisabled?: boolean;
  onRight?: () => void;
}) {
  return (
    <header className="grid h-[calc(56px+env(safe-area-inset-top))] shrink-0 grid-cols-[64px_1fr_82px] items-end border-b border-zinc-100 bg-white px-2 pb-2 pt-[env(safe-area-inset-top)]">
      <button
        type="button"
        onClick={onLeft}
        aria-label={leftLabel}
        className="grid h-11 w-11 place-items-center rounded-full text-zinc-950"
      >
        {leftIcon}
      </button>
      <h1 className="pb-3 text-center text-sm font-black text-zinc-950">{title}</h1>
      {rightLabel ? (
        <button
          type="button"
          onClick={onRight}
          disabled={rightDisabled}
          className="justify-self-end rounded-xl bg-natalo-600 px-3 py-2 text-sm font-black text-white disabled:bg-zinc-300"
        >
          {rightLabel}
        </button>
      ) : (
        <span />
      )}
    </header>
  );
}

function validatePickedVideoFile(file: File) {
  const lowerName = file.name.toLowerCase();
  const hasSupportedExtension = lowerName.endsWith(".mp4") || lowerName.endsWith(".mov");
  const hasSupportedMime =
    file.type === "video/mp4" ||
    file.type === "video/quicktime" ||
    file.type === "video/x-m4v" ||
    file.type === "";

  if (!hasSupportedExtension && !hasSupportedMime) {
    throw new Error("Format video harus MP4 atau MOV.");
  }
  if (file.type && !file.type.startsWith("video/")) {
    throw new Error("File harus berupa video.");
  }
  if (file.size <= 0) {
    throw new Error("File video belum bisa dibaca.");
  }
  if (file.size > MAX_SOURCE_VIDEO_SIZE) {
    throw new Error(
      `Ukuran video terlalu besar (${formatFileSize(file.size)}). Maksimal ${formatFileSize(MAX_SOURCE_VIDEO_SIZE)} — coba pilih video lebih pendek atau rekam dengan kualitas 1080p.`,
    );
  }
}

async function copyVideoToLocalFile(file: File) {
  const buffer = await file.arrayBuffer();
  const name = getLocalVideoFileName(file);
  return new File([buffer], name, {
    type: normalizeVideoMime(file),
    lastModified: Date.now(),
  });
}

function getLocalVideoFileName(file: File) {
  const cleanName = file.name.replace(/[^\w.\-]+/g, "-").replace(/^-+|-+$/g, "");
  if (cleanName) return cleanName;
  const extension = file.type === "video/quicktime" ? "mov" : "mp4";
  return `feed-video-${Date.now()}.${extension}`;
}

function normalizeVideoMime(file: File) {
  if (file.type) return file.type;
  return file.name.toLowerCase().endsWith(".mov") ? "video/quicktime" : "video/mp4";
}

function getFriendlyVideoPickError(error: unknown) {
  if (!(error instanceof Error)) return "Gagal membaca video.";
  if (
    error.message.startsWith("Format") ||
    error.message.startsWith("File") ||
    error.message.startsWith("Ukuran")
  ) {
    return error.message;
  }
  return "Video belum bisa dibaca. Pastikan format MP4/MOV dan file sudah tersimpan penuh di perangkat.";
}

function getVideoDebugBase(file: File) {
  return {
    platform: getRuntimePlatform(),
    originalName: file.name || "(unnamed)",
    originalPath: file.webkitRelativePath || "(not provided by browser)",
    size: file.size,
    mimeType: file.type || "(empty)",
    lastModified: file.lastModified || null,
  };
}

function getRuntimePlatform() {
  if (typeof window === "undefined") return "server";
  const cap = (
    window as Window & {
      Capacitor?: { getPlatform?: () => string; isNativePlatform?: () => boolean };
    }
  ).Capacitor;
  try {
    if (cap?.isNativePlatform?.()) return cap.getPlatform?.() ?? "capacitor";
  } catch {
    // Fall through to user-agent based platform label.
  }
  if (isIOS()) return "ios-web";
  if (/Android/i.test(navigator.userAgent)) return "android-web";
  return "web";
}

function debugFeedVideo(stage: string, details: Record<string, unknown>) {
  console.info(`[feed-video] ${stage}`, details);
}

function serializeError(error: unknown) {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
      stack: error.stack,
    };
  }
  return { message: String(error) };
}

function getStepTitle(step: FlowStep) {
  if (step === "pick") return "Pilih Video";
  if (step === "trim") return "Trim Video";
  if (step === "detail") return "Detail Postingan";
  if (step === "success") return "Postingan Berhasil Dikirim";
  if (step === "status") return "Video Saya";
  return "Mengunggah";
}

function formatDuration(seconds: number) {
  const safeSeconds = Math.max(0, Math.round(seconds));
  const minutes = Math.floor(safeSeconds / 60);
  const rest = safeSeconds % 60;
  return `${minutes}:${String(rest).padStart(2, "0")}`;
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}
