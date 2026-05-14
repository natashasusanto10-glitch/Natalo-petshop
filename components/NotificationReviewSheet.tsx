"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { hapticTap, hapticSuccess } from "@/lib/native/haptics";
import { pickPhoto } from "@/lib/photo-picker";

type OrderItem = {
  id: string;
  name: string;
  variantLabel: string | null;
  productId: string;
  productImage: string | null;
  reviewed: boolean;
};

type Props = {
  orderNumber: string;
  onClose: () => void;
};

export function NotificationReviewSheet({ orderNumber, onClose }: Props) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<OrderItem[]>([]);
  const [activeItem, setActiveItem] = useState<OrderItem | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fetch(`/api/orders/${encodeURIComponent(orderNumber)}`, { cache: "no-store" })
      .then(async (res) => {
        if (!res.ok) {
          const data = await res.json().catch(() => null);
          throw new Error(data?.message ?? `HTTP ${res.status}`);
        }
        return res.json();
      })
      .then((data) => {
        if (cancelled) return;
        const orderItems = (data?.order?.items ?? []) as OrderItem[];
        const reviewable = orderItems.filter((it) => !it.reviewed);
        setItems(reviewable);
        if (reviewable.length === 1) {
          setActiveItem(reviewable[0]);
        }
        setError(null);
      })
      .catch((err) => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : "Gagal memuat produk");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [orderNumber]);

  if (activeItem) {
    return (
      <ReviewSheet
        item={activeItem}
        onClose={() => {
          setActiveItem(null);
          if (items.length <= 1) onClose();
        }}
      />
    );
  }

  return (
    <SheetShell onClose={onClose} ariaLabel="Pilih produk untuk direview">
      <SheetHeader title="Beri Review" onClose={onClose} />
      <div className="p-5">
        {loading && (
          <div className="space-y-3">
            {[1, 2].map((i) => (
              <div key={i} className="h-20 animate-pulse rounded-xl bg-gray-100" />
            ))}
          </div>
        )}

        {!loading && error && (
          <div className="rounded-xl bg-red-50 p-4 text-sm text-red-700">{error}</div>
        )}

        {!loading && !error && items.length === 0 && (
          <div className="rounded-xl bg-gray-50 p-5 text-center">
            <p className="text-sm text-gray-600">
              Produk untuk direview tidak ditemukan. Silakan buka detail pesanan.
            </p>
            <a
              href={`/pesanan/${encodeURIComponent(orderNumber)}`}
              className="mt-3 inline-flex items-center justify-center rounded-full bg-blue-600 px-5 py-2 text-sm font-bold text-white"
            >
              Lihat Pesanan
            </a>
          </div>
        )}

        {!loading && !error && items.length > 1 && (
          <>
            <p className="mb-3 text-sm text-gray-500">Pilih produk yang ingin kamu review.</p>
            <ul className="space-y-3">
              {items.map((item) => (
                <li key={item.id}>
                  <button
                    type="button"
                    onClick={() => {
                      void hapticTap();
                      setActiveItem(item);
                    }}
                    className="flex w-full items-center gap-3 rounded-2xl border border-gray-100 bg-white p-3 text-left shadow-sm transition active:scale-[0.99] active:bg-gray-50"
                  >
                    <div className="h-14 w-14 shrink-0 overflow-hidden rounded-lg bg-gray-100">
                      {item.productImage ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={item.productImage} alt={item.name} className="h-full w-full object-cover" />
                      ) : (
                        <div className="flex h-full items-center justify-center text-2xl">🐾</div>
                      )}
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="line-clamp-2 text-sm font-semibold text-gray-900">{item.name}</p>
                      {item.variantLabel && (
                        <p className="text-xs text-natalo-600">{item.variantLabel}</p>
                      )}
                    </div>
                    <span className="shrink-0 whitespace-nowrap rounded-full bg-natalo-600 px-4 py-1.5 text-xs font-bold text-white">
                      ★ Review
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          </>
        )}
      </div>
    </SheetShell>
  );
}

function SheetShell({
  children,
  onClose,
  ariaLabel,
}: {
  children: React.ReactNode;
  onClose: () => void;
  ariaLabel: string;
}) {
  // Slide-up animation: start translated-down + opacity 0, animate to 0/1 on mount.
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(id);
  }, []);

  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, []);

  return (
    <div
      className={`fixed inset-0 z-[3000] flex items-end justify-center bg-black/40 transition-opacity duration-300 sm:items-center sm:p-4 ${
        mounted ? "opacity-100" : "opacity-0"
      }`}
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-label={ariaLabel}
    >
      <div
        className={`flex max-h-[90vh] w-full max-w-md flex-col overflow-hidden rounded-t-3xl bg-white shadow-2xl transition-transform duration-300 ease-out [transition-timing-function:cubic-bezier(0.2,0.8,0.2,1)] sm:rounded-3xl ${
          mounted ? "translate-y-0" : "translate-y-full sm:translate-y-4"
        }`}
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </div>
    </div>
  );
}

function SheetHeader({ title, onClose }: { title: string; onClose: () => void }) {
  return (
    <div className="relative shrink-0 border-b border-gray-100 px-5 pb-4 pt-3">
      <div className="mx-auto h-1 w-10 rounded-full bg-gray-200" aria-hidden="true" />
      <div className="mt-3 flex items-center justify-between">
        <h2 className="text-lg font-black text-gray-900">{title}</h2>
        <button
          type="button"
          onClick={onClose}
          className="flex h-9 w-9 items-center justify-center rounded-full text-gray-500 transition active:bg-gray-100"
          aria-label="Tutup"
        >
          ✕
        </button>
      </div>
    </div>
  );
}

function ReviewSheet({ item, onClose }: { item: OrderItem; onClose: () => void }) {
  const [rating, setRating] = useState(0);
  const [revealed, setRevealed] = useState(0);
  const [bounceIdx, setBounceIdx] = useState<number | null>(null);
  const [content, setContent] = useState("");
  const [imageUrls, setImageUrls] = useState<string[]>([]);
  const [uploading, setUploading] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState(false);
  const revealTimers = useRef<number[]>([]);

  function clearTimers() {
    revealTimers.current.forEach((id) => window.clearTimeout(id));
    revealTimers.current = [];
  }

  useEffect(() => () => clearTimers(), []);

  function handleStarTap(value: number) {
    if (rating === value) return;
    void hapticTap();
    setRating(value);
    setRevealed(0);
    setBounceIdx(null);
    clearTimers();
    // Sequential reveal: bintang 1→value, delay 40ms tiap step.
    for (let i = 1; i <= value; i++) {
      const id = window.setTimeout(() => {
        setRevealed(i);
        if (i === value) {
          setBounceIdx(i);
          window.setTimeout(() => setBounceIdx(null), 320);
        }
      }, i * 40);
      revealTimers.current.push(id);
    }
  }

  async function handleAddPhoto() {
    if (imageUrls.length >= 5) {
      setError("Maksimal 5 foto.");
      return;
    }
    setError("");
    setUploading(true);
    try {
      const result = await pickPhoto({ quality: 80, maxWidth: 1600, maxHeight: 1600, source: "prompt" });
      if (!result.ok) {
        if ("cancelled" in result) return;
        throw result.error;
      }
      const fd = new FormData();
      const ext = result.format === "jpeg" ? "jpg" : result.format;
      fd.append("file", result.blob, `review-photo.${ext}`);
      const res = await fetch("/api/reviews/upload", { method: "POST", body: fd });
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
          productId: item.productId,
          orderItemId: item.id,
          rating,
          title: null,
          content: content.trim() || null,
          imageUrls,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gagal kirim review");
      void hapticSuccess();
      setSuccess(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal kirim review");
    } finally {
      setSubmitting(false);
    }
  }

  if (success) {
    return (
      <SheetShell onClose={onClose} ariaLabel="Review terkirim">
        <div className="flex flex-col items-center px-6 pb-6 pt-8 text-center">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-green-100 text-3xl text-green-600">
            ✓
          </div>
          <h2 className="mt-4 text-xl font-black text-gray-950">Terima kasih!</h2>
          <p className="mt-2 text-sm text-gray-600">Ulasan kamu berhasil dikirim.</p>
          <p className="mt-1 text-sm text-gray-500">Ulasan kamu akan sangat membantu pembeli lainnya.</p>
          <Link
            href="/member/reviews"
            className="mt-6 inline-flex w-full justify-center rounded-full bg-blue-600 px-5 py-3 text-sm font-black text-white hover:bg-blue-700"
          >
            Lihat Ulasan Saya
          </Link>
          <button
            type="button"
            onClick={onClose}
            className="mt-3 inline-flex w-full justify-center rounded-full border border-gray-200 px-5 py-3 text-sm font-bold text-gray-700 hover:bg-gray-50"
          >
            Tutup
          </button>
        </div>
      </SheetShell>
    );
  }

  return (
    <SheetShell onClose={onClose} ariaLabel="Beri review produk">
      <SheetHeader title="Beri Review" onClose={onClose} />

      <div className="flex-1 overflow-y-auto px-5 py-4">
        {/* Product */}
        <div className="flex items-center gap-3">
          <div className="h-14 w-14 shrink-0 overflow-hidden rounded-lg bg-gray-100">
            {item.productImage ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={item.productImage} alt={item.name} className="h-full w-full object-cover" />
            ) : (
              <div className="flex h-full items-center justify-center text-2xl">🐾</div>
            )}
          </div>
          <div className="min-w-0">
            <p className="line-clamp-2 text-sm font-semibold text-gray-900">{item.name}</p>
            {item.variantLabel && (
              <p className="text-xs text-natalo-600">{item.variantLabel}</p>
            )}
          </div>
        </div>

        {/* Rating */}
        <div className="mt-5">
          <p className="text-sm font-bold text-gray-900">Bagaimana produk yang kamu beli?</p>
          <div className="mt-2 flex items-center gap-1" aria-label="Pilih rating">
            {[1, 2, 3, 4, 5].map((value) => {
              const lit = value <= revealed;
              const bounce = bounceIdx === value;
              return (
                <button
                  key={value}
                  type="button"
                  onClick={() => handleStarTap(value)}
                  className={`text-4xl leading-none transition-transform duration-150 active:scale-[0.98] ${
                    lit ? "text-amber-400" : "text-gray-300"
                  } ${bounce ? "[animation:nat-star-bounce_320ms_ease-out]" : ""}`}
                  aria-label={`${value} bintang`}
                >
                  ★
                </button>
              );
            })}
            {rating > 0 && (
              <span className="ml-2 text-xs font-bold text-gray-600">{rating}/5</span>
            )}
          </div>
        </div>

        {/* Content */}
        <div className="mt-5">
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            maxLength={2000}
            rows={4}
            placeholder="Ceritakan pengalaman kamu tentang produk ini..."
            className="w-full resize-none rounded-2xl border border-gray-200 px-4 py-3 text-sm outline-none focus:border-natalo-400"
          />
          <p className="mt-1 text-xs text-gray-500">
            Ulasan kamu membantu pembeli lain memilih produk yang tepat.
          </p>
        </div>

        {/* Photos */}
        <div className="mt-5">
          <p className="text-sm font-bold text-gray-900">
            Tambah foto produk yang diterima <span className="font-medium text-gray-500">(Opsional)</span>
          </p>
          <div className="mt-2 flex flex-wrap gap-2">
            {imageUrls.map((url, i) => (
              <div key={i} className="relative h-20 w-20 overflow-hidden rounded-xl border border-gray-100">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={url} alt="" className="h-full w-full object-cover" />
                <button
                  type="button"
                  onClick={() => removeImage(i)}
                  className="absolute right-1 top-1 flex h-5 w-5 items-center justify-center rounded-full bg-black/60 text-xs text-white"
                  aria-label="Hapus foto"
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
                className={`flex h-20 w-20 items-center justify-center rounded-xl border-2 border-dashed transition ${
                  uploading
                    ? "cursor-wait border-natalo-300 text-natalo-300"
                    : "border-gray-300 text-gray-400 hover:border-natalo-300 hover:text-natalo-500"
                }`}
                aria-label="Tambah foto"
              >
                {uploading ? (
                  <span className="text-sm">...</span>
                ) : (
                  <span className="text-2xl leading-none">📷+</span>
                )}
              </button>
            )}
          </div>
          <p className="mt-1 text-xs text-gray-500">Maksimal 5 foto · JPG/PNG · 5MB per foto</p>
        </div>

        {error && (
          <p className="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p>
        )}
      </div>

      {/* Sticky footer */}
      <div className="shrink-0 border-t border-gray-100 bg-white px-5 py-4 [padding-bottom:calc(1rem+env(safe-area-inset-bottom))]">
        <button
          type="button"
          onClick={submit}
          disabled={submitting || rating === 0}
          className="w-full rounded-full bg-natalo-600 py-3 text-sm font-black text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:bg-gray-300"
        >
          {submitting ? "Mengirim..." : "Kirim Ulasan"}
        </button>
      </div>

      <style jsx>{`
        @keyframes nat-star-bounce {
          0% {
            transform: scale(0.98);
          }
          40% {
            transform: scale(1.18);
          }
          70% {
            transform: scale(0.96);
          }
          100% {
            transform: scale(1);
          }
        }
      `}</style>
    </SheetShell>
  );
}
