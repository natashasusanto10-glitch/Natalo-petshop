"use client";

import { useEffect, useState } from "react";
import { ReviewModal } from "@/components/ReviewModal";

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
      <ReviewModal
        orderItemId={activeItem.id}
        productId={activeItem.productId}
        productName={activeItem.name}
        productImage={activeItem.productImage}
        variantLabel={activeItem.variantLabel}
        onClose={() => {
          // After submit or close: if more items remain, show picker again
          setActiveItem(null);
          if (items.length <= 1) onClose();
        }}
      />
    );
  }

  return (
    <div
      className="fixed inset-0 z-[3000] flex items-end justify-center bg-black/40 sm:items-center sm:p-4"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-label="Pilih produk untuk direview"
    >
      <div
        className="max-h-[85vh] w-full max-w-md overflow-y-auto rounded-t-2xl bg-white shadow-xl sm:rounded-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-100 bg-white p-5">
          <h2 className="text-lg font-black text-gray-900">Beri Review</h2>
          <button
            type="button"
            onClick={onClose}
            className="flex h-9 w-9 items-center justify-center rounded-full text-gray-500 transition active:bg-gray-100"
            aria-label="Tutup"
          >
            ✕
          </button>
        </div>

        <div className="p-5">
          {loading && (
            <div className="space-y-3">
              {[1, 2].map((i) => (
                <div key={i} className="h-20 animate-pulse rounded-xl bg-gray-100" />
              ))}
            </div>
          )}

          {!loading && error && (
            <div className="rounded-xl bg-red-50 p-4 text-sm text-red-700">
              {error}
            </div>
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
              <p className="mb-3 text-sm text-gray-500">
                Pilih produk yang ingin kamu review.
              </p>
              <ul className="space-y-3">
                {items.map((item) => (
                  <li key={item.id}>
                    <button
                      type="button"
                      onClick={() => setActiveItem(item)}
                      className="flex w-full items-center gap-3 rounded-2xl border border-gray-100 bg-white p-3 text-left shadow-sm transition active:scale-[0.99] active:bg-gray-50"
                    >
                      <div className="h-14 w-14 shrink-0 overflow-hidden rounded-lg bg-gray-100">
                        {item.productImage ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img
                            src={item.productImage}
                            alt={item.name}
                            className="h-full w-full object-cover"
                          />
                        ) : (
                          <div className="flex h-full items-center justify-center text-2xl">
                            🐾
                          </div>
                        )}
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="line-clamp-2 text-sm font-semibold text-gray-900">
                          {item.name}
                        </p>
                        {item.variantLabel && (
                          <p className="text-xs text-natalo-600">{item.variantLabel}</p>
                        )}
                      </div>
                      <span className="rounded-full bg-natalo-600 px-4 py-1.5 text-xs font-bold text-white">
                        ★ Review
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
