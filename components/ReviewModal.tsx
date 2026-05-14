"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { StarsInput } from "@/components/StarRating";
import { pickPhoto } from "@/lib/photo-picker";

interface Props {
  orderItemId: string;
  productId: string;
  productName: string;
  productImage: string | null;
  variantLabel: string | null;
  onClose: () => void;
}

export function ReviewModal({
  orderItemId,
  productId,
  productName,
  productImage,
  variantLabel,
  onClose,
}: Props) {
  const router = useRouter();
  const [rating, setRating] = useState(0);
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [imageUrls, setImageUrls] = useState<string[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [uploading, setUploading] = useState(false);

  useEffect(() => {
    const previous = document.body.dataset.reviewModalOpen;
    document.body.dataset.reviewModalOpen = "true";

    return () => {
      if (previous === undefined) {
        delete document.body.dataset.reviewModalOpen;
      } else {
        document.body.dataset.reviewModalOpen = previous;
      }
    };
  }, []);

  async function handleAddPhoto() {
    if (imageUrls.length >= 5) {
      setError("Maksimal 5 foto.");
      return;
    }

    setError("");
    setUploading(true);

    try {
      // Universal photo picker: native camera plugin di iOS/.ipa, file input di web.
      // Plugin auto-resize ke max 1600px + quality 80% — file size lebih kecil
      // dari raw HEIC iPhone (yang bisa 3-5MB).
      const result = await pickPhoto({
        quality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
        source: "prompt", // Action sheet: Take Photo / Photo Library
      });

      if (!result.ok) {
        // User cancelled — silent, no error
        if ("cancelled" in result) return;
        throw result.error;
      }

      // Upload ke endpoint existing
      const fd = new FormData();
      const ext = result.format === "jpeg" ? "jpg" : result.format;
      fd.append("file", result.blob, `review-photo.${ext}`);

      const res = await fetch("/api/reviews/upload", {
        method: "POST",
        body: fd,
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Upload gagal");
      setImageUrls((prev) => [...prev, data.url]);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload gagal");
    } finally {
      setUploading(false);
    }
  }

  function removeImage(idx: number) {
    setImageUrls((prev) => prev.filter((_, i) => i !== idx));
  }

  async function submit() {
    if (rating < 1) {
      setError("Pilih rating bintang dulu.");
      return;
    }
    setSubmitting(true);
    setError("");

    try {
      const res = await fetch("/api/reviews", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          productId,
          orderItemId,
          rating,
          title: title.trim() || null,
          content: content.trim() || null,
          imageUrls,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gagal kirim review");

      router.refresh();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal kirim review");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[3000] flex items-center justify-center bg-black/40 p-4">
      <div className="max-h-[90vh] w-full max-w-md overflow-y-auto rounded-2xl bg-white shadow-xl">
        {/* Header */}
        <div className="border-b border-gray-100 p-5">
          <h2 className="text-lg font-black text-gray-900">Beri Review</h2>
          <div className="mt-3 flex items-center gap-3">
            <div className="h-12 w-12 shrink-0 overflow-hidden rounded-lg bg-gray-100">
              {productImage ? (
                <img
                  src={productImage}
                  alt={productName}
                  className="h-full w-full object-cover"
                />
              ) : (
                <div className="flex h-full items-center justify-center text-2xl">
                  🐾
                </div>
              )}
            </div>
            <div className="min-w-0">
              <p className="line-clamp-2 text-sm font-semibold text-gray-900">
                {productName}
              </p>
              {variantLabel && (
                <p className="text-xs text-natalo-600">{variantLabel}</p>
              )}
            </div>
          </div>
        </div>

        {/* Body */}
        <div className="space-y-5 p-5">
          {/* Rating */}
          <div>
            <p className="mb-2 text-sm font-medium text-gray-700">
              Rating <span className="text-red-500">*</span>
            </p>
            <StarsInput value={rating} onChange={setRating} size="lg" />
          </div>

          {/* Title */}
          <div>
            <p className="mb-2 text-sm font-medium text-gray-700">
              Judul (opsional)
            </p>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              maxLength={100}
              placeholder="Misal: Anjing saya suka banget"
              className="w-full rounded-xl border border-gray-200 px-4 py-2.5 text-sm outline-none focus:border-natalo-400"
            />
          </div>

          {/* Content */}
          <div>
            <p className="mb-2 text-sm font-medium text-gray-700">
              Cerita (opsional)
            </p>
            <textarea
              value={content}
              onChange={(e) => setContent(e.target.value)}
              maxLength={2000}
              rows={4}
              placeholder="Ceritakan pengalaman kamu..."
              className="w-full rounded-xl border border-gray-200 px-4 py-2.5 text-sm outline-none focus:border-natalo-400"
            />
            <p className="mt-1 text-right text-xs text-gray-400">
              {content.length}/2000
            </p>
          </div>

          {/* Photos */}
          <div>
            <p className="mb-2 text-sm font-medium text-gray-700">
              Foto (opsional, max 5)
            </p>
            <div className="flex flex-wrap gap-2">
              {imageUrls.map((url, i) => (
                <div
                  key={i}
                  className="relative h-20 w-20 overflow-hidden rounded-lg border"
                >
                  <img
                    src={url}
                    alt=""
                    className="h-full w-full object-cover"
                  />
                  <button
                    type="button"
                    onClick={() => removeImage(i)}
                    className="absolute right-1 top-1 flex h-5 w-5 items-center justify-center rounded-full bg-black/60 text-xs text-white"
                  >
                    ×
                  </button>
                </div>
              ))}
              {imageUrls.length < 5 && (
                <button
                  type="button"
                  onClick={handleAddPhoto}
                  disabled={uploading}
                  className={`flex h-20 w-20 cursor-pointer items-center justify-center rounded-lg border-2 border-dashed text-2xl transition ${
                    uploading
                      ? "cursor-wait border-natalo-300 text-natalo-300"
                      : "border-gray-300 text-gray-300 hover:border-natalo-300 hover:text-natalo-300"
                  }`}
                  aria-label="Tambah foto review"
                >
                  {uploading ? "..." : "+"}
                </button>
              )}
            </div>
          </div>

          {error && (
            <p className="rounded-lg bg-red-50 p-3 text-sm text-red-600">
              {error}
            </p>
          )}
        </div>

        {/* Footer */}
        <div className="flex gap-3 border-t border-gray-100 p-5">
          <button
            onClick={onClose}
            disabled={submitting}
            className="flex-1 rounded-full border border-gray-200 py-3 text-sm font-bold text-gray-700 hover:bg-gray-50 disabled:opacity-50"
          >
            Batal
          </button>
          <button
            onClick={submit}
            disabled={submitting || rating === 0}
            className="flex-1 rounded-full bg-natalo-600 py-3 text-sm font-bold text-white hover:bg-natalo-700 disabled:bg-gray-300"
          >
            {submitting ? "Mengirim..." : "Kirim Review"}
          </button>
        </div>
      </div>
    </div>
  );
}
