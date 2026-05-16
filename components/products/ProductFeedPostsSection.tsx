"use client";

/**
 * "Postingan Pelanggan" section di product detail page — UGC video review
 * sebagai social proof. Tampilkan horizontal scrollable grid dari 12 post
 * teratas (sorted by likeCount), masing-masing card = thumbnail vertikal
 * 9:16 + author name + like count.
 *
 * Tap card → buka /feed?product=<slug> yang filter feed cuma post-post
 * yang tag produk ini. User bisa swipe vertical seperti Reels.
 *
 * Empty state: hide section kalau tidak ada post (jangan kasih ruang
 * kosong untuk "be the first poster" — terlalu invasive di product page).
 */
import Link from "next/link";
import Image from "next/image";
import { useEffect, useState } from "react";
import { FiHeart, FiPlay } from "react-icons/fi";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";

type FeedPostCard = {
  id: string;
  title: string;
  thumbnailUrl: string | null;
  videoDurationSec: number | null;
  likeCount: number;
  commentCount: number;
  createdAt: string;
  author: {
    id: string;
    name: string;
    role: "ADMIN" | "CUSTOMER";
  };
};

type Props = {
  productSlug: string;
};

export function ProductFeedPostsSection({ productSlug }: Props) {
  const [items, setItems] = useState<FeedPostCard[] | null>(null);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setItems(null);
    setError(false);
    fetch(`/api/products/${encodeURIComponent(productSlug)}/feed-posts`)
      .then((res) => {
        if (!res.ok) throw new Error("fetch failed");
        return res.json() as Promise<{ items: FeedPostCard[]; total: number }>;
      })
      .then((data) => {
        if (cancelled) return;
        setItems(data.items);
        setTotal(data.total);
      })
      .catch(() => {
        if (cancelled) return;
        setError(true);
        setItems([]);
      });
    return () => {
      cancelled = true;
    };
  }, [productSlug]);

  // Loading skeleton — 3 placeholder cards.
  if (items === null) {
    return (
      <section className="mt-2 bg-white px-4 py-5 md:mt-10 md:rounded-3xl md:border md:border-gray-100 md:p-6">
        <h2 className="text-base font-black text-gray-900 md:text-xl">
          Postingan Pelanggan
        </h2>
        <p className="mt-1 text-xs text-gray-500">
          Lihat video customer lain pakai produk ini
        </p>
        <div className="mt-4 flex gap-3 overflow-x-auto pb-2">
          {Array.from({ length: 3 }).map((_, i) => (
            <div
              key={i}
              className="aspect-[9/16] w-32 shrink-0 animate-pulse rounded-2xl bg-gray-100"
            />
          ))}
        </div>
      </section>
    );
  }

  // Hide section entirely kalau tidak ada post (avoid empty-state clutter
  // di product page).
  if (error || items.length === 0) return null;

  return (
    <section className="mt-2 bg-white px-4 py-5 md:mt-10 md:rounded-3xl md:border md:border-gray-100 md:p-6">
      <div className="flex items-end justify-between">
        <div>
          <h2 className="text-base font-black text-gray-900 md:text-xl">
            Postingan Pelanggan
          </h2>
          <p className="mt-1 text-xs text-gray-500">
            {total} video customer lain pakai produk ini
          </p>
        </div>
        {total > items.length && (
          <Link
            href={`/feed?product=${encodeURIComponent(productSlug)}`}
            className="text-[12px] font-black text-natalo-600 transition active:opacity-70"
          >
            Lihat semua →
          </Link>
        )}
      </div>

      {/* Horizontal scrollable card list */}
      <div className="mt-4 flex gap-3 overflow-x-auto pb-2 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {items.map((post) => (
          <Link
            key={post.id}
            href={`/feed?product=${encodeURIComponent(productSlug)}&post=${encodeURIComponent(post.id)}`}
            className="group relative aspect-[9/16] w-32 shrink-0 overflow-hidden rounded-2xl bg-gray-900 ring-1 ring-gray-200 transition active:scale-[0.98]"
          >
            {post.thumbnailUrl ? (
              <Image
                src={post.thumbnailUrl}
                alt={post.title}
                fill
                sizes="128px"
                placeholder="blur"
                blurDataURL={IMAGE_BLUR_GRAY}
                className="object-cover"
              />
            ) : (
              <div className="grid h-full w-full place-items-center bg-gradient-to-br from-gray-800 to-gray-950 text-white/50">
                <FiPlay className="h-8 w-8" />
              </div>
            )}
            {/* Gradient overlay buat readability */}
            <div className="pointer-events-none absolute inset-x-0 bottom-0 h-20 bg-gradient-to-t from-black/85 to-transparent" />
            {/* Play icon di top-right */}
            <div className="pointer-events-none absolute right-2 top-2 rounded-full bg-black/55 p-1.5 backdrop-blur-sm">
              <FiPlay className="h-3 w-3 fill-white stroke-white" />
            </div>
            {/* Footer: author + like count */}
            <div className="pointer-events-none absolute inset-x-2 bottom-2 text-white">
              <p className="truncate text-[11px] font-bold drop-shadow-[0_1px_2px_rgba(0,0,0,0.6)]">
                {post.author.role === "ADMIN"
                  ? "Natalo Petshop"
                  : post.author.name}
              </p>
              <div className="mt-1 flex items-center gap-1 text-[10px] font-bold">
                <FiHeart className="h-3 w-3 fill-white" />
                <span>{formatCount(post.likeCount)}</span>
              </div>
            </div>
          </Link>
        ))}
      </div>
    </section>
  );
}

function formatCount(count: number) {
  if (count >= 1_000_000) {
    return `${(count / 1_000_000).toFixed(count >= 10_000_000 ? 0 : 1).replace(/\.0$/, "")}M`;
  }
  if (count >= 1_000) {
    return `${(count / 1_000).toFixed(count >= 10_000 ? 0 : 1).replace(/\.0$/, "")}K`;
  }
  return String(count);
}
