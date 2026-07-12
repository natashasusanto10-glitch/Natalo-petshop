"use client";

/**
 * Admin create post form. Mendukung 4 jenis (spec section 4):
 *   1. VIDEO_ONLY     → video edukasi/info tanpa produk (tab REKOMENDASI)
 *   2. VIDEO_PRODUCT  → video jualan dgn produk terkait (tab REKOMENDASI)
 *   3. PROMO          → video promo dgn pricing diskon (auto tab PROMO)
 *
 * Note: PRODUCT_ONLY (card produk tanpa video) sengaja DIHAPUS dari UI
 * create — feed sekarang video-first. Kalau ingin showcase produk
 * tanpa video, pakai banner homepage atau landing page produk.
 * Existing PRODUCT_ONLY post tetap render di feed (backward compat).
 *
 * Flow:
 *   - Pilih kind
 *   - Isi title + description
 *   - Pilih video (untuk VIDEO_* dan PROMO opsional) → client-side thumb extract
 *   - Pilih produk (untuk VIDEO_PRODUCT, PROMO)
 *   - Promo fields (untuk PROMO)
 *   - Submit → POST /api/feed/posts → auto-ACTIVE
 */
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import { FiArrowLeft, FiUploadCloud, FiX } from "react-icons/fi";
import { formatRupiah } from "@/lib/format";
import {
  extractVideoThumbnail,
  readVideoMetadata,
  type VideoMetadata,
} from "@/lib/feed/video-thumbnail";
import { uploadToBunnyViaTus } from "@/lib/feed/tus-upload";
import {
  clearPendingUpload,
  getPendingUpload,
  savePendingUpload,
  useUploadLifecycle,
  type PendingUploadInfo,
} from "@/lib/feed/upload-lifecycle";
import {
  ADMIN_VIDEO_CONFIG,
  formatFileSize,
  MAX_SOURCE_VIDEO_SIZE,
} from "@/lib/feed/video-config";

// PRODUCT_ONLY sengaja TIDAK dimasukkan ke union ini — admin create hanya
// support kind yang punya video (VIDEO_ONLY, VIDEO_PRODUCT, PROMO).
// Existing PRODUCT_ONLY post tetap render di feed untuk backward compat,
// tapi tidak ada UI untuk create baru. Showcase produk tanpa video → pakai
// banner homepage / product landing page.
type Kind = "VIDEO_ONLY" | "VIDEO_PRODUCT" | "PROMO";

type ProductSummary = {
  id: string;
  slug: string;
  name: string;
  price: number;
  imageUrl: string | null;
};

const ACCEPT_VIDEO = "video/mp4,video/webm,video/quicktime";
const MAX_ADMIN_TAGGED_PRODUCTS = 5;

export function AdminFeedCreateClient() {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [kind, setKind] = useState<Kind>("VIDEO_ONLY");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  // AI generate judul + caption (topik + produk tertaut → Claude API).
  const [aiTopic, setAiTopic] = useState("");
  const [aiLoading, setAiLoading] = useState(false);
  const [aiError, setAiError] = useState<string | null>(null);
  const [videoFile, setVideoFile] = useState<File | null>(null);
  const [videoMeta, setVideoMeta] = useState<VideoMetadata | null>(null);
  const [thumbBlob, setThumbBlob] = useState<Blob | null>(null);
  const [thumbPreviewUrl, setThumbPreviewUrl] = useState<string | null>(null);
  const [productQuery, setProductQuery] = useState("");
  const [productResults, setProductResults] = useState<ProductSummary[]>([]);
  const [selectedProducts, setSelectedProducts] = useState<ProductSummary[]>([]);
  const [productLoading, setProductLoading] = useState(false);

  // Per-product promo pricing untuk kind=PROMO. Key = productId,
  // value = string input (kosong = no discount untuk produk itu).
  // Tujuan: 1 video PROMO bisa diskon banyak produk dengan harga
  // discount masing-masing yang admin set di sini.
  const [productPromos, setProductPromos] = useState<Record<string, string>>(
    {},
  );
  const [promoStarts, setPromoStarts] = useState("");
  const [promoEnds, setPromoEnds] = useState("");

  // Push notification saat publish (Feed Publish Push). Default OFF —
  // admin opt-in per post. pushInfo di-fetch sekali saat toggle pertama
  // ON supaya tidak selalu hit server tiap render.
  const [notifyOnPublish, setNotifyOnPublish] = useState(false);
  const [pushSegment, setPushSegment] = useState<
    "all" | "members" | "active30d"
  >("members");
  const [pushInfo, setPushInfo] = useState<{
    counts: { all: number; members: number; active30d: number };
    quota: { used: number; cap: number };
  } | null>(null);
  const [pushInfoLoading, setPushInfoLoading] = useState(false);
  const [testState, setTestState] = useState<"idle" | "sending" | "sent">(
    "idle",
  );
  const [testError, setTestError] = useState<string | null>(null);

  const [analyzing, setAnalyzing] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [progress, setProgress] = useState("");
  const [compressProgress, setCompressProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);
  // Track uploading state spesifik (sub-state dari submitting) supaya
  // lifecycle hook subscribe ke app state hanya saat upload jalan.
  const [uploading, setUploading] = useState(false);

  // Capacitor App lifecycle — saat app ke background mid-upload, switch
  // progress message + TUS auto-pause/resume saat foreground. Kalau
  // app ke-kill, pending state di localStorage bisa di-resume next
  // session pakai TUS fingerprint.
  useUploadLifecycle(uploading, {
    onSuspend: () => {
      setProgress(
        "Upload pause sementara — app di background. Buka kembali untuk lanjut.",
      );
    },
    onResume: () => {
      setProgress("Melanjutkan upload, mohon tunggu...");
    },
  });

  // Detect pending upload dari session sebelumnya (saved ke localStorage
  // sebelum upload start, dibersihkan saat sukses). Kalau ada + masih
  // dalam window 24 jam, tampil banner supaya admin bisa lanjut atau
  // discard. TUS fingerprint di-resolve otomatis saat file dipilih lagi
  // (tus-js-client findPreviousUploads match by file content hash).
  const [pendingUpload, setPendingUpload] = useState<PendingUploadInfo | null>(
    null,
  );
  useEffect(() => {
    setPendingUpload(getPendingUpload());
  }, []);

  // Semua kind yang admin bisa create sekarang punya video — PRODUCT_ONLY
  // di-hapus dari opsi UI (lihat header comment). needsVideo bisa di-
  // simplify jadi true, tapi explicit list dibiarkan supaya lebih jelas
  // saat baca code.
  const needsVideo = kind === "VIDEO_ONLY" || kind === "VIDEO_PRODUCT" || kind === "PROMO";
  const needsProduct = kind === "VIDEO_PRODUCT" || kind === "PROMO";
  // PROMO sekarang wajib video juga — tidak lagi banner-only — karena
  // PRODUCT_ONLY (use case banner) sudah dihapus.
  const videoOptional = false;

  // Reset state irrelevant saat kind berubah. Compute needs* di sini supaya
  // tidak butuh dependencies tambahan di effect.
  useEffect(() => {
    setError(null);
    const stillNeedsVideo =
      kind === "VIDEO_ONLY" || kind === "VIDEO_PRODUCT" || kind === "PROMO";
    const stillNeedsProduct =
      kind === "VIDEO_PRODUCT" || kind === "PROMO";
    if (!stillNeedsVideo) {
      setVideoFile(null);
      setVideoMeta(null);
      setThumbBlob(null);
      setThumbPreviewUrl((prev) => {
        if (prev) URL.revokeObjectURL(prev);
        return null;
      });
    }
    if (!stillNeedsProduct) setSelectedProducts([]);
  }, [kind]);

  const selectedProductIds = selectedProducts.map((product) => product.id);
  const selectedProductIdSet = new Set(selectedProductIds);

  // Generate judul + caption via AI dari topik + produk tertaut. Bisa jalan
  // kalau topik terisi ATAU ada produk di-tag. Hasil menimpa Judul & Deskripsi
  // (konfirmasi dulu kalau field sudah terisi) — admin tetap bisa edit.
  async function handleAiGenerate() {
    if (aiLoading) return;
    if (aiTopic.trim().length < 3 && selectedProducts.length === 0) {
      setAiError("Isi topik dulu (min 3 huruf) atau tag minimal satu produk.");
      return;
    }
    if (
      (title.trim() || description.trim()) &&
      !window.confirm("Timpa Judul & Deskripsi yang ada dengan hasil AI?")
    ) {
      return;
    }
    setAiLoading(true);
    setAiError(null);
    try {
      const res = await fetch("/api/admin/feed/generate-post", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          topic: aiTopic.trim(),
          kind,
          productIds: selectedProductIds,
        }),
      });
      const data = await res.json().catch(() => null);
      if (!res.ok) {
        setAiError(data?.error ?? "Gagal generate. Coba lagi.");
      } else {
        setTitle(String(data?.title ?? "").slice(0, 200));
        setDescription(String(data?.caption ?? "").slice(0, 2000));
      }
    } catch (err) {
      setAiError(
        err instanceof Error ? `Network error: ${err.message}` : "Network error",
      );
    } finally {
      setAiLoading(false);
    }
  }

  // Debounced product search
  useEffect(() => {
    if (!needsProduct || productQuery.trim().length < 2) {
      setProductResults([]);
      return;
    }
    const q = productQuery.trim();
    const timer = window.setTimeout(async () => {
      setProductLoading(true);
      try {
        const res = await fetch(`/api/admin/products?q=${encodeURIComponent(q)}&limit=10`);
        if (!res.ok) throw new Error();
        const data: { items?: ProductSummary[]; products?: ProductSummary[] } = await res
          .json()
          .catch(() => ({}));
        // Different shape kemungkinan — coba beberapa key umum.
        const arr = Array.isArray(data.items)
          ? data.items
          : Array.isArray(data.products)
            ? data.products
            : [];
        setProductResults(arr.slice(0, 10));
      } catch {
        setProductResults([]);
      } finally {
        setProductLoading(false);
      }
    }, 350);
    return () => window.clearTimeout(timer);
  }, [productQuery, needsProduct]);

  function addSelectedProduct(product: ProductSummary) {
    setSelectedProducts((current) => {
      if (current.some((item) => item.id === product.id)) return current;
      if (current.length >= MAX_ADMIN_TAGGED_PRODUCTS) {
        setError(`Maksimal ${MAX_ADMIN_TAGGED_PRODUCTS} produk terkait.`);
        return current;
      }
      setError(null);
      return [...current, product];
    });
    setProductQuery("");
    setProductResults([]);
  }

  function removeSelectedProduct(productId: string) {
    setSelectedProducts((current) =>
      current.filter((product) => product.id !== productId),
    );
    setProductPromos((prev) => {
      const next = { ...prev };
      delete next[productId];
      return next;
    });
  }

  async function handleVideoPick(file: File | null) {
    if (!file) return;
    setError(null);
    if (!file.type.startsWith("video/")) {
      setError("File yang dipilih bukan video. Pilih file format MP4, MOV, atau WebM.");
      return;
    }
    if (file.size > MAX_SOURCE_VIDEO_SIZE) {
      setError(
        `Ukuran video terlalu besar (${formatFileSize(file.size)}). Maksimal ${formatFileSize(MAX_SOURCE_VIDEO_SIZE)} — coba turunkan kualitas kamera ke 1080p (Settings → Camera → Record Video).`,
      );
      return;
    }
    setVideoFile(file);
    setAnalyzing(true);
    try {
      const meta = await readVideoMetadata(file);
      if (meta.durationSec < ADMIN_VIDEO_CONFIG.minDuration) {
        setError(
          `Video terlalu pendek (${Math.round(meta.durationSec)}s). Feed butuh minimal ${ADMIN_VIDEO_CONFIG.minDuration} detik.`,
        );
        setVideoFile(null);
        setVideoMeta(null);
        return;
      }
      if (meta.durationSec > ADMIN_VIDEO_CONFIG.maxDuration) {
        setError(
          `Video terlalu panjang (${Math.round(meta.durationSec)}s). Maksimal ${ADMIN_VIDEO_CONFIG.maxDuration} detik untuk feed.`,
        );
        setVideoFile(null);
        setVideoMeta(null);
        return;
      }
      setVideoMeta(meta);
      const thumb = await extractVideoThumbnail(file, {
        targetTimeSec: Math.min(1, meta.durationSec / 2),
      });
      setThumbBlob(thumb);
      if (thumbPreviewUrl) URL.revokeObjectURL(thumbPreviewUrl);
      setThumbPreviewUrl(URL.createObjectURL(thumb));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal proses video.");
      setVideoFile(null);
      setVideoMeta(null);
      setThumbBlob(null);
    } finally {
      setAnalyzing(false);
    }
  }

  // Toggle "Beri tahu pelanggan" ON → fetch push-info sekali (cache di
  // state pushInfo). Kalau sudah pernah di-fetch, tidak fetch ulang.
  async function handleNotifyToggle() {
    const next = !notifyOnPublish;
    setNotifyOnPublish(next);
    if (next && !pushInfo && !pushInfoLoading) {
      setPushInfoLoading(true);
      try {
        const res = await fetch("/api/admin/feed/push-info");
        if (res.ok) {
          const data = await res.json();
          setPushInfo(data);
          // Kuota sudah habis — jangan biarkan toggle nyala percuma
          // (server tetap skip kirim push kalau cap tercapai).
          if (data?.quota?.used >= data?.quota?.cap) {
            setNotifyOnPublish(false);
          }
        }
      } catch {
        // Diamkan — counts tetap fallback "–", tidak blokir toggle.
      } finally {
        setPushInfoLoading(false);
      }
    }
  }

  const quotaExhausted =
    !!pushInfo && pushInfo.quota.used >= pushInfo.quota.cap;

  // Tes push ke HP admin sendiri — butuh title terisi supaya preview
  // relevan. Tidak menyentuh cap/kuota publish-push yang sebenarnya.
  async function handleTestPush() {
    if (title.trim().length < 3) {
      setTestError("Isi judul dulu (min 3 huruf) untuk tes push.");
      return;
    }
    setTestError(null);
    setTestState("sending");
    try {
      const res = await fetch("/api/admin/feed/push-info", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: title.trim(),
          description: description.trim() || null,
        }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => null);
        setTestError(data?.error ?? "Gagal mengirim tes push.");
        setTestState("idle");
        return;
      }
      setTestState("sent");
      window.setTimeout(() => setTestState("idle"), 2000);
    } catch {
      setTestError("Network error saat kirim tes push.");
      setTestState("idle");
    }
  }

  async function handleSubmit() {
    setError(null);
    if (title.trim().length < 3) {
      setError("Judul minimal 3 karakter.");
      return;
    }
    if (needsVideo && !videoOptional && !videoFile) {
      setError("Video wajib untuk kind ini.");
      return;
    }
    if (needsProduct && selectedProducts.length === 0) {
      setError("Pilih produk yang terkait.");
      return;
    }
    if (kind === "PROMO") {
      // Setidaknya 1 produk harus punya promoPrice valid (> 0, < harga normal).
      const anyValid = selectedProducts.some((p) => {
        const raw = (productPromos[p.id] ?? "").trim();
        if (raw === "") return false;
        const n = Number(raw);
        return Number.isFinite(n) && n > 0 && n < p.price;
      });
      if (!anyValid) {
        setError(
          "Set minimal 1 harga promo per-produk (lebih kecil dari harga normal).",
        );
        return;
      }
      // Validate setiap nilai non-empty: harus < harga produknya.
      for (const p of selectedProducts) {
        const raw = (productPromos[p.id] ?? "").trim();
        if (raw === "") continue;
        const n = Number(raw);
        if (!Number.isFinite(n) || n <= 0 || n >= p.price) {
          setError(
            `Harga promo "${p.name}" harus angka positif < ${p.price}.`,
          );
          return;
        }
      }
    }

    setSubmitting(true);
    try {
      // Video path: Bunny direct upload. The server creates the FeedPost
      // row pre-filled with kind/tab/promo + a Bunny GUID, returns a
      // signed upload URL, and the Bunny webhook finalises encodingStatus
      // + videoUrl when transcoding completes. No client-side compression
      // — admin desktops would hang for minutes on long videos, and Bunny
      // handles every codec we throw at it.
      // Build per-product promo map untuk PROMO kind. Skip empty string
      // entries → null (no discount untuk produk itu).
      const productPromosPayload: Record<string, number | null> = {};
      if (kind === "PROMO") {
        for (const p of selectedProducts) {
          const raw = (productPromos[p.id] ?? "").trim();
          productPromosPayload[p.id] =
            raw === ""
              ? null
              : Number.isFinite(Number(raw))
                ? Number(raw)
                : null;
        }
      }

      if (videoFile) {
        setProgress("Menyiapkan upload, mohon tunggu...");
        const provisionBody = {
          title: title.trim() || "Postingan baru",
          description: description.trim() || null,
          kind,
          tab: kind === "PROMO" ? "PROMO" : "REKOMENDASI",
          productId: selectedProducts[0]?.id ?? null,
          productIds: selectedProductIds,
          // Legacy single-price fields kosong — per-product di productPromos.
          promoOriginalPrice: null,
          promoDiscountPrice: null,
          productPromos: kind === "PROMO" ? productPromosPayload : undefined,
          promoStartsAt: kind === "PROMO" && promoStarts ? promoStarts : null,
          promoEndsAt: kind === "PROMO" && promoEnds ? promoEnds : null,
          notifyOnPublish,
          pushSegment,
        };
        const provisionRes = await fetch("/api/feed/bunny/upload-url", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(provisionBody),
        });
        const provisionData = await provisionRes.json();
        if (!provisionRes.ok) {
          throw new Error(provisionData.error ?? "Gagal menyiapkan upload.");
        }

        // Hint untuk file besar: 200 MB di 4G ~5 menit, di sinyal lemah
        // bisa 15+ menit. Tampilkan ke user supaya tidak tutup tab.
        const sizeMB = videoFile.size / 1024 / 1024;
        const isLargeFile = sizeMB > 50;
        setProgress(
          isLargeFile
            ? `Mengunggah video ${sizeMB.toFixed(0)} MB — koneksi putus pun bisa lanjut otomatis...`
            : "Mengunggah video, mohon tunggu...",
        );

        // Save pending state ke localStorage SEBELUM upload mulai —
        // kalau app crash mid-upload, user bisa lihat banner di reopen.
        // TUS fingerprint sendiri sudah di-save terpisah oleh tus-js-client.
        savePendingUpload({
          postId: provisionData.postId,
          videoGuid: provisionData.videoGuid,
          filename: videoFile.name,
          sizeMB,
          startedAt: Date.now(),
        });
        setUploading(true);

        // TUS resumable upload (primary path). Kalau koneksi putus
        // di tengah, tus-js-client otomatis retry dengan exponential
        // backoff dan resume dari byte terakhir yang server konfirmasi.
        // File besar 200 MB di 4G yang signal-nya naik-turun tetap
        // bisa upload kelar tanpa start dari 0.
        //
        // Fallback ke simple PUT kalau:
        //   - Server tidak return TUS credentials (Bunny config error)
        //   - TUS gagal initial connect (very rare)
        const tusCredentials = provisionData.tus;
        if (tusCredentials) {
          try {
            await uploadToBunnyViaTus({
              file: videoFile,
              credentials: tusCredentials,
              filetype: videoFile.type || "video/mp4",
              title: videoFile.name,
              onProgress: (percent) => setCompressProgress(percent),
            });
            // Upload sukses → clear pending state.
            clearPendingUpload();
            setUploading(false);
          } catch (err) {
            // TUS gagal total — pending state tetap di localStorage
            // supaya user bisa retry next session (TUS fingerprint
            // di-keep oleh tus-js-client untuk resume).
            setUploading(false);
            const msg =
              err instanceof Error ? err.message : String(err);
            if (msg.toLowerCase().includes("abort")) {
              clearPendingUpload();
              throw new Error("Upload dibatalkan.");
            }
            throw new Error(
              "Upload terputus berkali-kali. Coba lagi dengan koneksi yang lebih stabil — atau gunakan WiFi.",
            );
          }
        } else {
          // Legacy simple PUT (fallback kalau server tidak return TUS creds).
          await new Promise<void>((resolve, reject) => {
            const xhr = new XMLHttpRequest();
            xhr.open("PUT", provisionData.uploadUrl, true);
            xhr.setRequestHeader(
              "AccessKey",
              provisionData.uploadHeaders.AccessKey,
            );
            xhr.setRequestHeader(
              "Content-Type",
              "application/octet-stream",
            );
            xhr.upload.onprogress = (e) => {
              if (e.lengthComputable) {
                setCompressProgress(Math.round((e.loaded / e.total) * 100));
              }
            };
            xhr.onload = () => {
              if (xhr.status >= 200 && xhr.status < 300) resolve();
              else
                reject(
                  new Error(
                    `Upload gagal (HTTP ${xhr.status}). Coba lagi dengan koneksi yang lebih stabil.`,
                  ),
                );
            };
            xhr.onerror = () =>
              reject(
                new Error(
                  "Upload terputus. Coba lagi dengan koneksi yang lebih stabil — atau gunakan WiFi.",
                ),
              );
            xhr.ontimeout = () =>
              reject(
                new Error(
                  "Upload terlalu lama (timeout). Coba lagi dengan koneksi yang lebih cepat.",
                ),
              );
            xhr.timeout = 30 * 60 * 1000;
            xhr.send(videoFile);
          });
          clearPendingUpload();
          setUploading(false);
        }

        // Done with PUT. Bunny will encode + fire webhook → encodingStatus=
        // ready. Admin gets ACTIVE+publishedAt set already by upload-url
        // endpoint. Jangan tahan admin di layar ini menunggu encoding; untuk
        // video besar, waiting 1-2 menit terasa seperti upload macet.
        const postId = provisionData.postId as string | undefined;
        if (postId) {
          void fetch("/api/admin/feed/bunny-reconcile", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ postId }),
          }).catch(() => {
            // Webhook/reconcile berikutnya tetap akan menyelesaikan status.
          });
        }

        setProgress(
          "Upload selesai. Video sedang diproses di background dan akan muncul otomatis saat siap.",
        );
        await new Promise((r) => setTimeout(r, 700));
        router.push("/admin/feed");
        router.refresh();
        return;
      }

      // No video (e.g., PROMO banner-only). Fall back to the legacy JSON
      // /api/feed/posts endpoint which doesn't go through Bunny at all.
      setProgress("Menyimpan post...");
      const tab = kind === "PROMO" ? "PROMO" : "REKOMENDASI";
      const body = {
        kind,
        tab,
        title: title.trim(),
        description: description.trim() || null,
        videoUrl: null,
        thumbnailUrl: null,
        videoMimeType: null,
        videoSizeBytes: null,
        videoDurationSec: null,
        videoWidth: null,
        videoHeight: null,
        productId: selectedProducts[0]?.id ?? null,
        productIds: selectedProductIds,
        // Legacy single-price kosong — pakai productPromos map.
        promoOriginalPrice: null,
        promoDiscountPrice: null,
        productPromos: kind === "PROMO" ? productPromosPayload : undefined,
        promoStartsAt: kind === "PROMO" && promoStarts ? promoStarts : null,
        promoEndsAt: kind === "PROMO" && promoEnds ? promoEnds : null,
        notifyOnPublish,
        pushSegment,
      };
      const res = await fetch("/api/feed/posts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gagal membuat post.");

      router.push("/admin/feed");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal");
    } finally {
      setSubmitting(false);
      setUploading(false);
      setProgress("");
      setCompressProgress(0);
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <header className="flex items-center gap-3">
        <button
          type="button"
          onClick={() => router.back()}
          aria-label="Kembali"
          className="grid h-9 w-9 place-items-center rounded-full bg-white shadow-sm"
        >
          <FiArrowLeft className="h-4 w-4 text-gray-700" />
        </button>
        <h1 className="text-base font-black text-gray-900">Buat Post Feed</h1>
      </header>

      {/* Pending upload banner — tampil kalau ada upload yg belum selesai
          dari session sebelumnya (app crash, force close, dll). Admin
          re-pilih file yang sama → TUS resume otomatis dari byte
          terakhir, tidak start dari 0. */}
      {pendingUpload && !submitting && (
        <div className="flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-3">
          <div className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-amber-100 text-amber-700">
            <FiUploadCloud className="h-4 w-4" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-xs font-extrabold text-amber-900">
              Upload sebelumnya belum selesai
            </p>
            <p className="mt-0.5 text-[11px] text-amber-800">
              File: {pendingUpload.filename} ({pendingUpload.sizeMB.toFixed(0)} MB).
              Pilih file yang sama lagi untuk lanjutkan dari titik
              terakhir — tidak perlu upload ulang.
            </p>
            <button
              type="button"
              onClick={() => {
                clearPendingUpload();
                setPendingUpload(null);
              }}
              className="mt-1 text-[11px] font-bold text-amber-700 underline"
            >
              Buang dan mulai baru
            </button>
          </div>
        </div>
      )}

      {/* Kind selector */}
      <section className="rounded-2xl border border-gray-100 bg-white p-3">
        <p className="mb-2 text-xs font-extrabold text-gray-700">Jenis post</p>
        <div className="grid grid-cols-2 gap-2">
          {(
            [
              { v: "VIDEO_ONLY", l: "Video Edukasi", d: "Tanpa produk" },
              { v: "VIDEO_PRODUCT", l: "Video + Produk", d: "Konten jualan" },
              { v: "PROMO", l: "Promo Produk", d: "Diskon per-produk" },
            ] as { v: Kind; l: string; d: string }[]
          ).map((opt) => (
            <button
              key={opt.v}
              type="button"
              onClick={() => setKind(opt.v)}
              className={`rounded-2xl border p-3 text-left text-xs font-extrabold transition ${
                kind === opt.v
                  ? "border-natalo-600 bg-natalo-50 text-natalo-700"
                  : "border-gray-200 bg-white text-gray-700 active:bg-gray-50"
              }`}
            >
              <p>{opt.l}</p>
              <p className="mt-0.5 text-[10px] font-semibold text-gray-500">{opt.d}</p>
            </button>
          ))}
        </div>
      </section>

      {/* Video picker */}
      {needsVideo && (
        <section className="rounded-2xl border border-gray-100 bg-white p-3">
          <p className="mb-2 text-xs font-extrabold text-gray-700">
            Video {videoOptional && <span className="text-gray-400">(opsional)</span>}
          </p>
          {videoFile && thumbPreviewUrl ? (
            <div className="space-y-2">
              <div className="relative aspect-[9/16] w-full max-w-[200px] overflow-hidden rounded-xl bg-gray-100">
                <Image src={thumbPreviewUrl} alt="" fill sizes="200px" className="object-cover" unoptimized />
                <button
                  type="button"
                  onClick={() => {
                    setVideoFile(null);
                    setVideoMeta(null);
                    if (thumbPreviewUrl) URL.revokeObjectURL(thumbPreviewUrl);
                    setThumbPreviewUrl(null);
                    setThumbBlob(null);
                  }}
                  className="absolute right-2 top-2 grid h-7 w-7 place-items-center rounded-full bg-black/60 text-white"
                  aria-label="Hapus video"
                >
                  <FiX className="h-3.5 w-3.5" />
                </button>
              </div>
              <p className="text-[11px] text-gray-500">
                {videoFile.name} · {(videoFile.size / 1024 / 1024).toFixed(1)} MB
                {videoMeta && ` · ${Math.round(videoMeta.durationSec)}s`}
              </p>
            </div>
          ) : (
            <>
              <input
                ref={fileInputRef}
                type="file"
                accept={ACCEPT_VIDEO}
                className="hidden"
                onChange={(e) => handleVideoPick(e.target.files?.[0] ?? null)}
              />
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                disabled={analyzing}
                className="flex w-full items-center justify-center gap-2 rounded-xl border-2 border-dashed border-gray-200 py-4 text-xs font-extrabold text-gray-600 transition active:bg-gray-50 disabled:opacity-50"
              >
                <FiUploadCloud className="h-4 w-4" />
                {analyzing
                  ? "Memproses..."
                  : `Pilih video (${ADMIN_VIDEO_CONFIG.minDuration}-${ADMIN_VIDEO_CONFIG.maxDuration}s · maks ${formatFileSize(MAX_SOURCE_VIDEO_SIZE)})`}
              </button>
            </>
          )}
        </section>
      )}

      {/* Title + description */}
      <section className="space-y-3 rounded-2xl border border-gray-100 bg-white p-3">
        {/* AI generate — topik + produk tertaut → judul & caption */}
        <div className="rounded-xl border border-purple-200 bg-purple-50/60 p-2.5">
          <label htmlFor="ai-topic" className="text-xs font-extrabold text-purple-800">
            ✨ Bantu tulis dengan AI
          </label>
          <div className="mt-1.5 flex gap-2">
            <input
              id="ai-topic"
              type="text"
              value={aiTopic}
              onChange={(e) => setAiTopic(e.target.value)}
              placeholder="Topik singkat, mis. grooming kucing musim panas"
              maxLength={120}
              className="min-w-0 flex-1 rounded-lg border border-purple-200 bg-white px-3 py-2 text-sm focus:border-purple-500 focus:outline-none"
            />
            <button
              type="button"
              onClick={() => void handleAiGenerate()}
              disabled={aiLoading}
              className="inline-flex shrink-0 items-center gap-1.5 rounded-lg bg-purple-600 px-3 py-2 text-xs font-bold text-white hover:bg-purple-700 disabled:cursor-not-allowed disabled:bg-purple-300"
            >
              {aiLoading ? (
                <>
                  <span
                    className="h-3 w-3 animate-spin rounded-full border-2 border-white/70 border-t-transparent"
                    aria-hidden
                  />
                  Membuat…
                </>
              ) : (
                "Generate"
              )}
            </button>
          </div>
          <p className="mt-1 text-[11px] text-purple-700/80">
            Dari topik + produk yang di-tag. Hasil bisa kamu edit sebelum publish.
          </p>
          {aiError && <p className="mt-1 text-[11px] text-red-600">⚠️ {aiError}</p>}
        </div>

        <div>
          <label htmlFor="title" className="text-xs font-extrabold text-gray-700">
            Judul <span className="text-red-500">*</span>
          </label>
          <input
            id="title"
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={200}
            className="mt-1 w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none"
          />
        </div>
        <div>
          <label htmlFor="desc" className="text-xs font-extrabold text-gray-700">
            Deskripsi
          </label>
          <textarea
            id="desc"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={3}
            maxLength={2000}
            className="mt-1 w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none"
          />
        </div>
      </section>

      {/* Beri tahu pelanggan — push notification opsional saat publish */}
      <section className="rounded-2xl border border-gray-100 bg-white p-3">
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="text-xs font-extrabold text-gray-700">
              Beri tahu pelanggan
            </p>
            <p className="mt-0.5 text-[11px] font-semibold text-gray-500">
              {notifyOnPublish
                ? "Push dikirim saat post ini tayang"
                : "Post tayang tanpa notifikasi"}
            </p>
          </div>
          <button
            type="button"
            role="switch"
            aria-checked={notifyOnPublish}
            disabled={quotaExhausted}
            onClick={() => void handleNotifyToggle()}
            className={`relative h-[26px] w-11 shrink-0 rounded-full transition-colors disabled:cursor-not-allowed disabled:opacity-60 ${
              notifyOnPublish ? "bg-natalo-600" : "bg-gray-200"
            }`}
          >
            <span
              className={`absolute top-0.5 h-[22px] w-[22px] rounded-full bg-white shadow transition-transform ${
                notifyOnPublish ? "translate-x-[22px]" : "translate-x-0.5"
              }`}
            />
          </button>
        </div>

        {notifyOnPublish && (
          <div className="mt-3 space-y-3">
            {pushInfoLoading && !pushInfo ? (
              <p className="text-[11px] font-bold text-gray-400">
                Memuat info kuota...
              </p>
            ) : (
              <p
                className={`rounded-xl px-3 py-2 text-[11px] font-bold ${
                  quotaExhausted
                    ? "bg-red-50 text-red-700"
                    : "bg-green-50 text-green-700"
                }`}
              >
                Kuota push hari ini:{" "}
                {pushInfo
                  ? `${Math.max(pushInfo.quota.cap - pushInfo.quota.used, 0)} dari ${pushInfo.quota.cap} tersisa`
                  : "–"}
              </p>
            )}

            <div className="space-y-2">
              {(
                [
                  {
                    v: "all",
                    l: "Semua pelanggan",
                    d: "Semua yang mengizinkan notifikasi. Untuk konten penting saja.",
                  },
                  {
                    v: "members",
                    l: "Member",
                    d: "Pernah belanja — paling relevan untuk promo dan produk.",
                    badge: "Disarankan",
                  },
                  {
                    v: "active30d",
                    l: "Aktif 30 hari",
                    d: "Belanja dalam sebulan terakhir — paling kecil risiko ganggu.",
                  },
                ] as {
                  v: "all" | "members" | "active30d";
                  l: string;
                  d: string;
                  badge?: string;
                }[]
              ).map((opt) => (
                <button
                  key={opt.v}
                  type="button"
                  onClick={() => setPushSegment(opt.v)}
                  className={`w-full rounded-xl border p-2.5 text-left transition ${
                    pushSegment === opt.v
                      ? "border-natalo-600 bg-natalo-50"
                      : "border-gray-200 bg-white active:bg-gray-50"
                  }`}
                >
                  <div className="flex items-center gap-2">
                    <p
                      className={`text-xs font-extrabold ${
                        pushSegment === opt.v ? "text-natalo-700" : "text-gray-700"
                      }`}
                    >
                      {opt.l}
                    </p>
                    {opt.badge && (
                      <span className="rounded-full bg-natalo-100 px-1.5 py-0.5 text-[9px] font-extrabold text-natalo-700">
                        {opt.badge}
                      </span>
                    )}
                    <span className="ml-auto shrink-0 text-[11px] font-bold text-gray-400">
                      {pushInfo ? pushInfo.counts[opt.v] : "–"}
                    </span>
                  </div>
                  <p className="mt-0.5 text-[10px] font-semibold text-gray-500">
                    {opt.d}
                  </p>
                </button>
              ))}
            </div>

            <button
              type="button"
              onClick={() => void handleTestPush()}
              disabled={testState === "sending"}
              className="w-full rounded-xl border border-gray-200 bg-white py-2 text-xs font-extrabold text-gray-700 transition active:bg-gray-50 disabled:opacity-50"
            >
              {testState === "sent"
                ? "Terkirim ke HP kamu ✓"
                : testState === "sending"
                  ? "Mengirim..."
                  : "Tes ke HP saya dulu"}
            </button>
            {testError && (
              <p className="text-[11px] font-bold text-red-600">{testError}</p>
            )}

            <p className="text-[10px] font-semibold text-gray-400">
              Video dikirim setelah selesai diproses, bukan saat upload.
            </p>
          </div>
        )}
      </section>

      {/* Product picker */}
      {needsProduct && (
        <section className="rounded-2xl border border-gray-100 bg-white p-3">
          <div className="mb-2 flex items-center justify-between gap-3">
            <p className="text-xs font-extrabold text-gray-700">
              Produk terkait <span className="text-red-500">*</span>
            </p>
            <span className="text-[11px] font-extrabold text-gray-400">
              {selectedProducts.length}/{MAX_ADMIN_TAGGED_PRODUCTS}
            </span>
          </div>

          {selectedProducts.length > 0 && (
            <div className="mb-3 space-y-2">
              {selectedProducts.map((product, index) => {
                const promoRaw = productPromos[product.id] ?? "";
                const promoNum = Number(promoRaw);
                const hasValidPromo =
                  promoRaw.trim() !== "" &&
                  Number.isFinite(promoNum) &&
                  promoNum > 0 &&
                  promoNum < product.price;
                const discountPct = hasValidPromo
                  ? Math.round(
                      ((product.price - promoNum) / product.price) * 100,
                    )
                  : 0;
                return (
                  <div
                    key={product.id}
                    className="rounded-xl bg-natalo-50 p-2"
                  >
                    <div className="flex items-center gap-3">
                      {product.imageUrl && (
                        <Image
                          src={product.imageUrl}
                          alt=""
                          width={40}
                          height={40}
                          className="h-10 w-10 rounded-lg object-cover"
                        />
                      )}
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-xs font-extrabold text-natalo-800">
                          {product.name}
                        </p>
                        <p className="text-[11px] font-semibold text-natalo-600">
                          {index === 0 ? "Produk utama · " : ""}
                          Harga normal {formatRupiah(product.price)}
                        </p>
                      </div>
                      <button
                        type="button"
                        onClick={() => removeSelectedProduct(product.id)}
                        className="grid h-8 w-8 place-items-center rounded-full text-natalo-700 transition active:bg-natalo-100"
                        aria-label={`Hapus ${product.name}`}
                      >
                        <FiX className="h-4 w-4" />
                      </button>
                    </div>
                    {kind === "PROMO" && (
                      <div className="mt-2 rounded-lg border border-rose-200 bg-rose-50/70 p-2.5">
                        <label className="block">
                          <span className="text-[11px] font-bold text-rose-800">
                            Harga Promo (Rp) — kosongkan kalau tidak diskon
                          </span>
                          <input
                            type="number"
                            inputMode="numeric"
                            value={promoRaw}
                            onChange={(e) =>
                              setProductPromos((prev) => ({
                                ...prev,
                                [product.id]: e.target.value,
                              }))
                            }
                            placeholder={`< ${product.price}`}
                            className="mt-0.5 w-full rounded-lg border border-rose-200 bg-white px-3 py-2 text-sm focus:border-rose-500 focus:outline-none"
                          />
                        </label>
                        {hasValidPromo ? (
                          <p className="mt-1.5 text-[11px] font-bold text-rose-800">
                            Hemat {formatRupiah(product.price - promoNum)} ·{" "}
                            {discountPct}% off
                          </p>
                        ) : promoRaw.trim() !== "" &&
                          Number.isFinite(promoNum) &&
                          promoNum >= product.price ? (
                          <p className="mt-1.5 text-[11px] font-bold text-amber-700">
                            Harus lebih kecil dari harga normal.
                          </p>
                        ) : null}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}

          {selectedProducts.length >= MAX_ADMIN_TAGGED_PRODUCTS ? (
            <p className="rounded-xl bg-gray-50 px-3 py-2 text-[11px] font-bold text-gray-500">
              Maksimal {MAX_ADMIN_TAGGED_PRODUCTS} produk terkait sudah dipilih.
            </p>
          ) : (
            <>
              <input
                type="text"
                placeholder={
                  selectedProducts.length > 0
                    ? "Cari produk tambahan..."
                    : "Cari produk (min 2 huruf)..."
                }
                value={productQuery}
                onChange={(e) => setProductQuery(e.target.value)}
                className="w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none"
              />
              {productLoading && (
                <p className="mt-2 text-center text-[11px] font-bold text-gray-400">Mencari...</p>
              )}
              {productResults.length > 0 && (
                <ul className="mt-2 max-h-60 overflow-y-auto rounded-xl border border-gray-100">
                  {productResults.map((p) => {
                    const selected = selectedProductIdSet.has(p.id);
                    return (
                      <li key={p.id}>
                        <button
                          type="button"
                          onClick={() => addSelectedProduct(p)}
                          disabled={selected}
                          className="flex w-full items-center gap-2 border-b border-gray-50 px-2 py-2 text-left text-xs transition last:border-0 hover:bg-gray-50 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:opacity-60"
                        >
                          {p.imageUrl && (
                            <Image
                              src={p.imageUrl}
                              alt=""
                              width={32}
                              height={32}
                              className="h-8 w-8 rounded-lg object-cover"
                            />
                          )}
                          <span className="min-w-0 flex-1 truncate font-bold">
                            {p.name}
                          </span>
                          <span className="shrink-0 text-natalo-600">
                            {selected ? "Dipilih" : formatRupiah(p.price)}
                          </span>
                        </button>
                      </li>
                    );
                  })}
                </ul>
              )}
            </>
          )}
        </section>
      )}

      {/* Promo schedule (per-product pricing diset di list produk di atas) */}
      {kind === "PROMO" && (
        <section className="space-y-3 rounded-2xl border border-gray-100 bg-white p-3">
          <div>
            <p className="text-xs font-extrabold text-gray-700">
              Jadwal promo (opsional)
            </p>
            <p className="text-[11px] font-semibold text-gray-500">
              Harga promo set per-produk di daftar produk di atas. Promo
              tetap aktif tanpa jadwal.
            </p>
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="text-[11px] font-bold text-gray-600">Mulai</label>
              <input
                type="datetime-local"
                value={promoStarts}
                onChange={(e) => setPromoStarts(e.target.value)}
                className="mt-0.5 w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-xs"
              />
            </div>
            <div>
              <label className="text-[11px] font-bold text-gray-600">Berakhir</label>
              <input
                type="datetime-local"
                value={promoEnds}
                onChange={(e) => setPromoEnds(e.target.value)}
                className="mt-0.5 w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-xs"
              />
            </div>
          </div>
        </section>
      )}

      {error && (
        <p className="rounded-2xl bg-red-50 p-3 text-sm font-bold text-red-700">{error}</p>
      )}

      {/* Loading overlay — full-screen blocker saat submitting. Kompres
          video di Bunny butuh 30s-2 menit, kalau user cuma lihat tombol
          disabled mereka kemungkinan close tab. Overlay ini bikin jelas:
          ada proses jalan, jangan ganggu. */}
      {submitting && (
        <div className="fixed inset-0 z-[200] flex items-center justify-center bg-black/55 px-6 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-3xl bg-white p-6 text-center shadow-2xl">
            <div
              className="mx-auto h-12 w-12 animate-spin rounded-full border-4 border-natalo-100 border-t-natalo-600"
              aria-hidden
            />
            <p className="mt-4 text-sm font-extrabold text-gray-900">
              {progress || "Memproses..."}
            </p>
            {/* Progress bar saat upload PUT — compressProgress > 0 hanya
                terisi di fase XHR upload. */}
            {compressProgress > 0 && compressProgress < 100 && (
              <>
                <div className="mt-4 h-2 w-full overflow-hidden rounded-full bg-gray-100">
                  <div
                    className="h-full rounded-full bg-natalo-600 transition-all duration-200"
                    style={{ width: `${compressProgress}%` }}
                  />
                </div>
                <p className="mt-2 text-xs font-bold text-gray-500">
                  {compressProgress}%
                </p>
              </>
            )}
            <p className="mt-4 text-[11px] font-semibold text-gray-400">
              Mohon jangan tutup halaman ini sampai selesai.
            </p>
          </div>
        </div>
      )}

      <button
        type="button"
        onClick={handleSubmit}
        disabled={submitting}
        className="sticky bottom-4 w-full rounded-full bg-natalo-600 py-3 text-sm font-extrabold text-white shadow-lg transition active:scale-[0.98] disabled:bg-gray-300"
      >
        {submitting ? progress || "Memproses..." : "Publish Post"}
      </button>
    </div>
  );
}
