"use client";

/**
 * Satu card di feed list. Render:
 * - Video player (kalau ada videoUrl) atau thumbnail produk (kalau PRODUCT_ONLY)
 * - Author badge (Natalo Official untuk admin, nama biasa untuk user)
 * - Title + description
 * - Product card kecil (kalau ada productId)
 * - Promo pricing (kalau kind=PROMO)
 * - Like + comment buttons (like optimistic update)
 *
 * Spec 10.9 — produk di feed cuma card ringan, detail full di /products/[slug].
 */
import Link from "next/link";
import Image from "next/image";
import { useState } from "react";
import { FiHeart, FiMessageCircle, FiShoppingCart } from "react-icons/fi";
import { formatRupiah } from "@/lib/format";
import { hapticTap } from "@/lib/native/haptics";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import type { FeedPostListItem } from "@/lib/feed/types";
import { FeedVideoPlayer } from "./FeedVideoPlayer";

type Props = {
  post: FeedPostListItem;
  onOpenComments: (postId: string) => void;
};

export function FeedVideoCard({ post, onOpenComments }: Props) {
  const [liked, setLiked] = useState(post.viewerLiked);
  const [likeCount, setLikeCount] = useState(post.likeCount);
  const [likeBusy, setLikeBusy] = useState(false);

  const isAdmin = post.author.role === "ADMIN";
  const product = post.product;
  const promo = post.promo;
  const hasVideo = Boolean(post.videoUrl);

  async function toggleLike() {
    if (likeBusy) return;
    setLikeBusy(true);
    // Optimistic update — spec 10.8. UI berubah instan, rollback kalau gagal.
    const prevLiked = liked;
    const prevCount = likeCount;
    setLiked(!prevLiked);
    setLikeCount(prevLiked ? Math.max(0, prevCount - 1) : prevCount + 1);
    hapticTap();
    try {
      const res = await fetch(`/api/feed/posts/${post.id}/like`, { method: "POST" });
      if (!res.ok) throw new Error("Like failed");
      const data: { liked: boolean; likeCount: number } = await res.json();
      // Sync server state — kalau race, server is source of truth.
      setLiked(data.liked);
      setLikeCount(data.likeCount);
    } catch {
      // Rollback
      setLiked(prevLiked);
      setLikeCount(prevCount);
    } finally {
      setLikeBusy(false);
    }
  }

  return (
    <article className="overflow-hidden rounded-3xl border border-gray-100 bg-white shadow-sm">
      {/* Header: author + badge */}
      <header className="flex items-center gap-2 px-4 py-3">
        <div className="flex h-9 w-9 items-center justify-center rounded-full bg-natalo-100 text-xs font-black text-natalo-700">
          {isAdmin ? "N" : initial(post.author.name)}
        </div>
        <div className="min-w-0 flex-1">
          <p className="flex items-center gap-1.5 truncate text-sm font-extrabold text-gray-900">
            {isAdmin ? "Natalo Petshop" : post.author.name}
            {isAdmin && (
              <span className="rounded-full bg-natalo-600 px-1.5 py-0.5 text-[9px] font-black uppercase tracking-wide text-white">
                Official
              </span>
            )}
          </p>
          <p className="text-[11px] font-semibold text-gray-400">
            {formatRelativeTime(post.publishedAt ?? post.createdAt)}
          </p>
        </div>
      </header>

      {/* Media area */}
      {hasVideo && post.videoUrl ? (
        <div className="px-4">
          <FeedVideoPlayer
            postId={post.id}
            videoUrl={post.videoUrl}
            thumbnailUrl={post.thumbnailUrl}
            durationSec={post.videoDurationSec}
            aspectRatio={
              post.videoWidth && post.videoHeight
                ? post.videoWidth / post.videoHeight
                : 9 / 16
            }
          />
        </div>
      ) : product?.imageUrl ? (
        // PRODUCT_ONLY — render thumbnail produk full-width
        <Link href={`/products/${product.slug}`} className="block px-4">
          <div className="relative aspect-square w-full overflow-hidden rounded-2xl bg-gray-100">
            <Image
              src={product.imageUrl}
              alt={product.name}
              fill
              sizes="(max-width: 768px) 100vw, 480px"
              placeholder="blur"
              blurDataURL={IMAGE_BLUR_GRAY}
              className="object-cover"
            />
          </div>
        </Link>
      ) : null}

      {/* Body */}
      <div className="space-y-3 px-4 py-3">
        <h2 className="text-sm font-extrabold leading-snug text-gray-900">{post.title}</h2>
        {post.description && (
          <p className="line-clamp-3 text-xs leading-relaxed text-gray-600">
            {post.description}
          </p>
        )}

        {/* Promo pricing block */}
        {promo && (
          <div className="rounded-2xl bg-red-50 p-3">
            <p className="text-[11px] font-bold uppercase tracking-wide text-red-600">
              Promo
            </p>
            <div className="mt-1 flex items-baseline gap-2">
              <span className="text-base font-black text-red-700">
                {formatRupiah(promo.discountPrice)}
              </span>
              <span className="text-xs text-gray-400 line-through">
                {formatRupiah(promo.originalPrice)}
              </span>
            </div>
          </div>
        )}

        {/* Product card ringan (admin VIDEO_PRODUCT atau community tag) */}
        {product && (
          <Link
            href={`/products/${product.slug}`}
            className="flex items-center gap-3 rounded-2xl border border-gray-100 bg-gray-50 p-2.5 transition active:bg-gray-100"
          >
            {product.imageUrl && (
              <div className="relative h-14 w-14 shrink-0 overflow-hidden rounded-xl bg-white">
                <Image
                  src={product.imageUrl}
                  alt={product.name}
                  fill
                  sizes="56px"
                  placeholder="blur"
                  blurDataURL={IMAGE_BLUR_GRAY}
                  className="object-cover"
                />
              </div>
            )}
            <div className="min-w-0 flex-1">
              <p className="line-clamp-2 text-xs font-extrabold text-gray-900">
                {product.name}
              </p>
              <p className="mt-0.5 text-sm font-black text-natalo-600">
                {formatRupiah(product.discountPrice ?? product.price)}
              </p>
            </div>
            {isAdmin && product.stock > 0 && (
              <button
                type="button"
                aria-label="Lihat produk"
                className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-natalo-600 text-white transition active:scale-95"
              >
                <FiShoppingCart className="h-4 w-4" />
              </button>
            )}
          </Link>
        )}
      </div>

      {/* Footer actions */}
      <footer className="flex items-center gap-4 border-t border-gray-100 px-4 py-2.5">
        <button
          type="button"
          onClick={toggleLike}
          aria-label={liked ? "Batal suka" : "Suka"}
          aria-pressed={liked}
          className="flex items-center gap-1.5 text-sm font-bold text-gray-600 transition active:scale-95"
        >
          <FiHeart
            className={`h-5 w-5 transition ${liked ? "fill-red-500 stroke-red-500" : ""}`}
          />
          <span>{likeCount}</span>
        </button>
        <button
          type="button"
          onClick={() => onOpenComments(post.id)}
          aria-label="Komentar"
          className="flex items-center gap-1.5 text-sm font-bold text-gray-600 transition active:scale-95"
        >
          <FiMessageCircle className="h-5 w-5" />
          <span>{post.commentCount}</span>
        </button>
      </footer>
    </article>
  );
}

function initial(name: string): string {
  return name.trim().charAt(0).toUpperCase() || "?";
}

function formatRelativeTime(iso: string) {
  const d = new Date(iso);
  const diff = Date.now() - d.getTime();
  const sec = Math.floor(diff / 1000);
  if (sec < 60) return "Baru saja";
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min} menit lalu`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr} jam lalu`;
  const day = Math.floor(hr / 24);
  if (day < 7) return `${day} hari lalu`;
  return d.toLocaleDateString("id-ID", { day: "numeric", month: "short", year: "numeric" });
}
