"use client";

/**
 * Admin create post form. Mendukung 4 jenis (spec section 4):
 *   1. VIDEO_ONLY     → video edukasi/info tanpa produk (tab REKOMENDASI)
 *   2. PRODUCT_ONLY   → card produk tanpa video (tab REKOMENDASI)
 *   3. VIDEO_PRODUCT  → video jualan dgn produk terkait (tab REKOMENDASI)
 *   4. PROMO          → banner/video promo dgn pricing diskon (auto tab PROMO)
 *
 * Flow:
 *   - Pilih kind
 *   - Isi title + description
 *   - Pilih video (untuk VIDEO_* dan PROMO opsional) → client-side thumb extract
 *   - Pilih produk (untuk PRODUCT_ONLY, VIDEO_PRODUCT, PROMO)
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
import {
  ADMIN_VIDEO_CONFIG,
  formatFileSize,
  MAX_SOURCE_VIDEO_SIZE,
} from "@/lib/feed/video-config";

type Kind = "VIDEO_ONLY" | "PRODUCT_ONLY" | "VIDEO_PRODUCT" | "PROMO";

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
  const [videoFile, setVideoFile] = useState<File | null>(null);
  const [videoMeta, setVideoMeta] = useState<VideoMetadata | null>(null);
  const [thumbBlob, setThumbBlob] = useState<Blob | null>(null);
  const [thumbPreviewUrl, setThumbPreviewUrl] = useState<string | null>(null);
  const [productQuery, setProductQuery] = useState("");
  const [productResults, setProductResults] = useState<ProductSummary[]>([]);
  const [selectedProducts, setSelectedProducts] = useState<ProductSummary[]>([]);
  const [productLoading, setProductLoading] = useState(false);

  const [promoOriginal, setPromoOriginal] = useState("");
  const [promoDiscount, setPromoDiscount] = useState("");
  const [promoStarts, setPromoStarts] = useState("");
  const [promoEnds, setPromoEnds] = useState("");

  const [analyzing, setAnalyzing] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [progress, setProgress] = useState("");
  const [compressProgress, setCompressProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const needsVideo = kind === "VIDEO_ONLY" || kind === "VIDEO_PRODUCT" || kind === "PROMO";
  const needsProduct = kind === "PRODUCT_ONLY" || kind === "VIDEO_PRODUCT" || kind === "PROMO";
  const videoOptional = kind === "PROMO"; // PROMO bisa banner-only tanpa video

  // Reset state irrelevant saat kind berubah. Compute needs* di sini supaya
  // tidak butuh dependencies tambahan di effect.
  useEffect(() => {
    setError(null);
    const stillNeedsVideo =
      kind === "VIDEO_ONLY" || kind === "VIDEO_PRODUCT" || kind === "PROMO";
    const stillNeedsProduct =
      kind === "PRODUCT_ONLY" || kind === "VIDEO_PRODUCT" || kind === "PROMO";
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
  }

  async function handleVideoPick(file: File | null) {
    if (!file) return;
    setError(null);
    if (!file.type.startsWith("video/")) {
      setError("File harus video.");
      return;
    }
    if (file.size > MAX_SOURCE_VIDEO_SIZE) {
      setError(`Video mentah maksimal ${formatFileSize(MAX_SOURCE_VIDEO_SIZE)}.`);
      return;
    }
    setVideoFile(file);
    setAnalyzing(true);
    try {
      const meta = await readVideoMetadata(file);
      if (meta.durationSec < ADMIN_VIDEO_CONFIG.minDuration) {
        setError(`Video terlalu pendek. Minimal ${ADMIN_VIDEO_CONFIG.minDuration} detik.`);
        setVideoFile(null);
        setVideoMeta(null);
        return;
      }
      if (meta.durationSec > ADMIN_VIDEO_CONFIG.maxDuration) {
        setError(`Video terlalu panjang. Maksimal ${ADMIN_VIDEO_CONFIG.maxDuration} detik.`);
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
      const orig = Number(promoOriginal);
      const disc = Number(promoDiscount);
      if (!orig || !disc || disc >= orig) {
        setError("Harga promo harus lebih kecil dari harga normal.");
        return;
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
      if (videoFile) {
        setProgress("Menyiapkan upload...");
        const provisionBody = {
          title: title.trim() || "Postingan baru",
          description: description.trim() || null,
          kind,
          tab: kind === "PROMO" ? "PROMO" : "REKOMENDASI",
          productId: selectedProducts[0]?.id ?? null,
          productIds: selectedProductIds,
          promoOriginalPrice: kind === "PROMO" ? Number(promoOriginal) || null : null,
          promoDiscountPrice: kind === "PROMO" ? Number(promoDiscount) || null : null,
          promoStartsAt: kind === "PROMO" && promoStarts ? promoStarts : null,
          promoEndsAt: kind === "PROMO" && promoEnds ? promoEnds : null,
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

        setProgress("Mengunggah video...");
        await new Promise<void>((resolve, reject) => {
          const xhr = new XMLHttpRequest();
          xhr.open("PUT", provisionData.uploadUrl, true);
          xhr.setRequestHeader("AccessKey", provisionData.uploadHeaders.AccessKey);
          xhr.setRequestHeader("Content-Type", "application/octet-stream");
          xhr.upload.onprogress = (e) => {
            if (e.lengthComputable) {
              setCompressProgress(Math.round((e.loaded / e.total) * 100));
            }
          };
          xhr.onload = () => {
            if (xhr.status >= 200 && xhr.status < 300) resolve();
            else reject(new Error(`Upload gagal (HTTP ${xhr.status})`));
          };
          xhr.onerror = () => reject(new Error("Network error saat upload."));
          xhr.send(videoFile);
        });

        // Done. Bunny will encode + fire webhook → encodingStatus=ready.
        // Admin gets ACTIVE+publishedAt set already by the upload-url
        // endpoint, so the post will appear in the feed as soon as
        // encoding finishes (usually <1 min for short clips).
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
        promoOriginalPrice: kind === "PROMO" ? Number(promoOriginal) : null,
        promoDiscountPrice: kind === "PROMO" ? Number(promoDiscount) : null,
        promoStartsAt: kind === "PROMO" && promoStarts ? promoStarts : null,
        promoEndsAt: kind === "PROMO" && promoEnds ? promoEnds : null,
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

      {/* Kind selector */}
      <section className="rounded-2xl border border-gray-100 bg-white p-3">
        <p className="mb-2 text-xs font-extrabold text-gray-700">Jenis post</p>
        <div className="grid grid-cols-2 gap-2">
          {(
            [
              { v: "VIDEO_ONLY", l: "Video Edukasi", d: "Tanpa produk" },
              { v: "VIDEO_PRODUCT", l: "Video + Produk", d: "Konten jualan" },
              { v: "PRODUCT_ONLY", l: "Produk Saja", d: "Card tanpa video" },
              { v: "PROMO", l: "Promo Produk", d: "Diskon + pricing" },
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
                  : `Pilih video (${ADMIN_VIDEO_CONFIG.minDuration}-${ADMIN_VIDEO_CONFIG.maxDuration}s, raw max ${formatFileSize(MAX_SOURCE_VIDEO_SIZE)})`}
              </button>
            </>
          )}
        </section>
      )}

      {/* Title + description */}
      <section className="space-y-3 rounded-2xl border border-gray-100 bg-white p-3">
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
              {selectedProducts.map((product, index) => (
                <div
                  key={product.id}
                  className="flex items-center gap-3 rounded-xl bg-natalo-50 p-2"
                >
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
                      {formatRupiah(product.price)}
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
              ))}
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

      {/* Promo fields */}
      {kind === "PROMO" && (
        <section className="space-y-3 rounded-2xl border border-gray-100 bg-white p-3">
          <p className="text-xs font-extrabold text-gray-700">Detail promo</p>
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="text-[11px] font-bold text-gray-600">
                Harga Normal <span className="text-red-500">*</span>
              </label>
              <input
                type="number"
                value={promoOriginal}
                onChange={(e) => setPromoOriginal(e.target.value)}
                className="mt-0.5 w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm"
              />
            </div>
            <div>
              <label className="text-[11px] font-bold text-gray-600">
                Harga Promo <span className="text-red-500">*</span>
              </label>
              <input
                type="number"
                value={promoDiscount}
                onChange={(e) => setPromoDiscount(e.target.value)}
                className="mt-0.5 w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm"
              />
            </div>
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

      <button
        type="button"
        onClick={handleSubmit}
        disabled={submitting}
        className="sticky bottom-4 w-full rounded-full bg-natalo-600 py-3 text-sm font-extrabold text-white shadow-lg transition active:scale-[0.98] disabled:bg-gray-300"
      >
        {submitting
          ? progress === "Mengunggah video..." && compressProgress > 0
            ? `${progress} ${compressProgress}%`
            : progress || "Memproses..."
          : "Publish Post"}
      </button>
    </div>
  );
}
