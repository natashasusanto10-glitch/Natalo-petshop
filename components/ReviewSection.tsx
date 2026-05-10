"use client";

import { useEffect, useState } from "react";
import { Stars } from "@/components/StarRating";
import { ExternalLink } from "@/components/ExternalLink";

type Review = {
  id: string;
  rating: number;
  title: string | null;
  content: string | null;
  variantLabel: string | null;
  helpfulCount: number;
  createdAt: string;
  userName: string;
  images: string[];
  reply: { content: string; createdAt: string } | null;
};

type Summary = {
  avgRating: number;
  reviewCount: number;
  ratingBreakdown: Record<string, number>;
};

interface Props {
  productSlug: string;
}

export function ReviewSection({ productSlug }: Props) {
  const [summary, setSummary] = useState<Summary | null>(null);
  const [reviews, setReviews] = useState<Review[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<{ rating?: number; withImage?: boolean; sort: string }>({
    sort: "newest",
  });

  useEffect(() => {
    fetch(`/api/products/${productSlug}/reviews/summary`)
      .then((r) => r.json())
      .then(setSummary)
      .catch(() => {});
  }, [productSlug]);

  useEffect(() => {
    setLoading(true);
    const params = new URLSearchParams({ sort: filter.sort });
    if (filter.rating) params.set("rating", String(filter.rating));
    if (filter.withImage) params.set("with_image", "true");

    fetch(`/api/products/${productSlug}/reviews?${params}`)
      .then((r) => r.json())
      .then((data) => {
        setReviews(data.reviews ?? []);
        setNextCursor(data.nextCursor ?? null);
      })
      .finally(() => setLoading(false));
  }, [productSlug, filter]);

  async function loadMore() {
    if (!nextCursor) return;
    const params = new URLSearchParams({ sort: filter.sort, cursor: nextCursor });
    if (filter.rating) params.set("rating", String(filter.rating));
    if (filter.withImage) params.set("with_image", "true");
    const data = await fetch(`/api/products/${productSlug}/reviews?${params}`).then((r) => r.json());
    setReviews((prev) => [...prev, ...(data.reviews ?? [])]);
    setNextCursor(data.nextCursor ?? null);
  }

  async function toggleHelpful(reviewId: string) {
    const res = await fetch(`/api/reviews/${reviewId}/helpful`, { method: "POST" });
    if (res.ok) {
      const { helpfulCount } = await res.json();
      setReviews((prev) =>
        prev.map((r) => (r.id === reviewId ? { ...r, helpfulCount } : r))
      );
    } else {
      const { error } = await res.json();
      alert(error ?? "Gagal vote");
    }
  }

  return (
    <section className="mt-16 border-t border-gray-100 pt-10">
      <h2 className="text-2xl font-black text-gray-900">Rating & Review</h2>

      {/* Summary panel */}
      {summary && summary.reviewCount > 0 ? (
        <div className="mt-6 grid gap-6 rounded-2xl border border-gray-100 bg-gray-50 p-6 sm:grid-cols-[180px_1fr]">
          <div className="text-center">
            <p className="text-5xl font-black text-amber-500">{summary.avgRating.toFixed(1)}</p>
            <Stars rating={summary.avgRating} size="md" />
            <p className="mt-1 text-sm text-gray-500">{summary.reviewCount} review</p>
          </div>
          <div className="space-y-1">
            {[5, 4, 3, 2, 1].map((star) => {
              const count = Number(summary.ratingBreakdown[star] ?? 0);
              const pct = summary.reviewCount > 0 ? (count / summary.reviewCount) * 100 : 0;
              return (
                <div key={star} className="flex items-center gap-3 text-sm">
                  <span className="w-8 text-amber-500">{star}★</span>
                  <div className="h-2 flex-1 overflow-hidden rounded-full bg-gray-200">
                    <div
                      className="h-full bg-amber-400 transition-all"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                  <span className="w-10 text-right text-gray-500">{count}</span>
                </div>
              );
            })}
          </div>
        </div>
      ) : (
        <div className="mt-6 rounded-2xl border border-gray-100 bg-gray-50 p-8 text-center">
          <p className="text-4xl">🌟</p>
          <p className="mt-3 text-sm text-gray-500">Belum ada review. Jadi yang pertama!</p>
        </div>
      )}

      {/* Filter */}
      {summary && summary.reviewCount > 0 && (
        <div className="mt-6 flex flex-wrap items-center gap-2">
          <FilterChip
            active={!filter.rating && !filter.withImage}
            onClick={() => setFilter({ sort: filter.sort })}
          >
            Semua
          </FilterChip>
          {[5, 4, 3, 2, 1].map((r) => (
            <FilterChip
              key={r}
              active={filter.rating === r}
              onClick={() =>
                setFilter((f) => ({ ...f, rating: f.rating === r ? undefined : r }))
              }
            >
              {r}★ ({summary.ratingBreakdown[r] ?? 0})
            </FilterChip>
          ))}
          <FilterChip
            active={filter.withImage === true}
            onClick={() => setFilter((f) => ({ ...f, withImage: !f.withImage }))}
          >
            📷 Dengan foto
          </FilterChip>

          <select
            value={filter.sort}
            onChange={(e) => setFilter((f) => ({ ...f, sort: e.target.value }))}
            className="ml-auto rounded-full border border-gray-200 bg-white px-4 py-1.5 text-sm font-medium text-gray-700"
          >
            <option value="newest">Terbaru</option>
            <option value="helpful">Paling membantu</option>
            <option value="rating_high">Rating tertinggi</option>
            <option value="rating_low">Rating terendah</option>
          </select>
        </div>
      )}

      {/* List */}
      <div className="mt-6 space-y-4">
        {loading ? (
          <p className="text-sm text-gray-400">Memuat review...</p>
        ) : reviews.length === 0 && summary && summary.reviewCount > 0 ? (
          <p className="text-sm text-gray-400">Tidak ada review yang cocok dengan filter.</p>
        ) : (
          reviews.map((r) => <ReviewCard key={r.id} review={r} onHelpful={() => toggleHelpful(r.id)} />)
        )}
      </div>

      {nextCursor && (
        <button
          onClick={loadMore}
          className="mx-auto mt-6 block rounded-full border border-gray-200 px-6 py-2 text-sm font-bold text-gray-700 hover:border-natalo-300 hover:text-natalo-600"
        >
          Muat lebih banyak
        </button>
      )}
    </section>
  );
}

function FilterChip({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-full border px-4 py-1.5 text-sm font-semibold transition ${
        active
          ? "border-natalo-600 bg-natalo-600 text-white"
          : "border-gray-200 bg-white text-gray-600 hover:border-natalo-300"
      }`}
    >
      {children}
    </button>
  );
}

function ReviewCard({ review, onHelpful }: { review: Review; onHelpful: () => void }) {
  const date = new Date(review.createdAt).toLocaleDateString("id-ID", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });

  return (
    <div className="rounded-2xl border border-gray-100 bg-white p-5">
      <div className="flex items-center justify-between gap-2">
        <div>
          <p className="font-semibold text-gray-900">{review.userName}</p>
          <div className="mt-1 flex items-center gap-2">
            <Stars rating={review.rating} size="sm" />
            <span className="text-xs text-gray-400">{date}</span>
          </div>
        </div>
      </div>

      {review.variantLabel && (
        <p className="mt-2 text-xs text-gray-500">Varian: {review.variantLabel}</p>
      )}

      {review.title && (
        <p className="mt-3 font-semibold text-gray-900">{review.title}</p>
      )}
      {review.content && (
        <p className="mt-2 text-sm text-gray-700 whitespace-pre-line">{review.content}</p>
      )}

      {review.images.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-2">
          {review.images.map((url, i) => (
            <ExternalLink key={i} href={url}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={url}
                alt={`Foto review ${i + 1}`}
                className="h-20 w-20 rounded-lg object-cover hover:opacity-90"
              />
            </ExternalLink>
          ))}
        </div>
      )}

      <div className="mt-3 flex items-center gap-3">
        <button
          onClick={onHelpful}
          className="flex items-center gap-1.5 rounded-full border border-gray-200 px-3 py-1 text-xs font-semibold text-gray-600 hover:border-natalo-300 hover:text-natalo-600"
        >
          👍 Membantu ({review.helpfulCount})
        </button>
      </div>

      {review.reply && (
        <div className="mt-4 rounded-xl bg-natalo-50 p-4">
          <p className="text-xs font-bold text-natalo-800">💬 Balasan dari Penjual</p>
          <p className="mt-1 text-sm text-gray-700 whitespace-pre-line">{review.reply.content}</p>
        </div>
      )}
    </div>
  );
}
