"use client";

import Link from "next/link";
import Image from "next/image";
import type { ReactNode } from "react";
import { useState } from "react";
import {
  FiHeart,
  FiMessageCircle,
  FiPackage,
  FiSend,
  FiShoppingCart,
} from "react-icons/fi";
import { BottomSheet } from "@/components/BottomSheet";
import { formatRupiah } from "@/lib/format";
import { hapticTap } from "@/lib/native/haptics";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import { shareContent } from "@/lib/share";
import type { FeedPostListItem } from "@/lib/feed/types";
import { FeedVideoPlayer } from "./FeedVideoPlayer";

type Props = {
  post: FeedPostListItem;
  /** Position in the parent feed list. Threaded down to FeedVideoPlayer so
   * it can compute distance-from-active and pick the right preload tier. */
  index: number;
  onOpenComments: (postId: string) => void;
};

export function FeedVideoCard({ post, index, onOpenComments }: Props) {
  const [liked, setLiked] = useState(post.viewerLiked);
  const [likeCount, setLikeCount] = useState(post.likeCount);
  const [likeBusy, setLikeBusy] = useState(false);
  const [shareCount, setShareCount] = useState(post.shareCount ?? 0);
  const [productSheetOpen, setProductSheetOpen] = useState(false);

  const isAdmin = post.author.role === "ADMIN";
  const product = post.product;
  const hasVideo = Boolean(post.videoUrl);
  const isCommunity = post.kind === "COMMUNITY";
  const productHref = product ? `/products/${product.slug}` : "#";

  async function toggleLike() {
    if (likeBusy) return;
    setLikeBusy(true);
    const prevLiked = liked;
    const prevCount = likeCount;
    setLiked(!prevLiked);
    setLikeCount(prevLiked ? Math.max(0, prevCount - 1) : prevCount + 1);
    hapticTap();
    try {
      const res = await fetch(`/api/feed/posts/${post.id}/like`, { method: "POST" });
      if (!res.ok) throw new Error("Like failed");
      const data: { liked: boolean; likeCount: number } = await res.json();
      setLiked(data.liked);
      setLikeCount(data.likeCount);
    } catch {
      setLiked(prevLiked);
      setLikeCount(prevCount);
    } finally {
      setLikeBusy(false);
    }
  }

  async function handleShare() {
    hapticTap();
    const path = `/feed?post=${post.id}`;
    const url =
      typeof window !== "undefined" ? `${window.location.origin}${path}` : path;
    const result = await shareContent({
      title: post.title,
      text: post.description ?? "Lihat video Natalo Petshop ini.",
      url,
    });
    // Only credit a real share — cancelled / failed shares don't bump
    // the counter. Optimistic update; server returns the canonical value.
    const counted =
      result.method === "native" ||
      result.method === "web-share" ||
      result.method === "clipboard";
    if (!counted) return;
    const prev = shareCount;
    setShareCount(prev + 1);
    try {
      const res = await fetch(`/api/feed/posts/${post.id}/share`, {
        method: "POST",
      });
      if (!res.ok) throw new Error("Share count update failed");
      const data: { shareCount: number } = await res.json();
      setShareCount(data.shareCount);
    } catch {
      setShareCount(prev);
    }
  }

  return (
    <article className="relative min-h-full snap-start overflow-hidden bg-black text-white shadow-sm md:rounded-[28px]">
      <div className="absolute inset-0">
        {hasVideo && post.videoUrl ? (
          <FeedVideoPlayer
            postId={post.id}
            index={index}
            videoUrl={post.videoUrl}
            thumbnailUrl={post.thumbnailUrl}
            durationSec={post.videoDurationSec}
            aspectRatio={
              post.videoWidth && post.videoHeight
                ? post.videoWidth / post.videoHeight
                : 9 / 16
            }
            className="h-full min-h-full rounded-none [&>img]:object-cover"
          />
        ) : product?.imageUrl ? (
          <Link href={productHref} className="block h-full">
            <Image
              src={product.imageUrl}
              alt={product.name}
              fill
              sizes="(max-width: 768px) 100vw, 480px"
              placeholder="blur"
              blurDataURL={IMAGE_BLUR_GRAY}
              className="object-cover"
            />
          </Link>
        ) : (
          <div className="grid h-full place-items-center bg-gradient-to-br from-natalo-700 to-slate-950">
            <FiPackage className="h-16 w-16 text-white/50" />
          </div>
        )}
      </div>

      <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-black/35 via-black/5 to-black/82" />

      <div className="absolute right-5 z-[2] flex flex-col items-center gap-5 [bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+6.25rem)] md:bottom-8">
        <ActionButton
          label={formatEngagementCount(likeCount)}
          ariaLabel={liked ? "Batal suka" : "Suka"}
          pressed={liked}
          onClick={toggleLike}
        >
          <FiHeart className={`h-[33px] w-[33px] ${liked ? "fill-red-500 stroke-red-500" : ""}`} />
        </ActionButton>
        <ActionButton
          label={formatEngagementCount(post.commentCount)}
          ariaLabel="Komentar"
          onClick={() => onOpenComments(post.id)}
        >
          <FiMessageCircle className="h-[33px] w-[33px]" />
        </ActionButton>
        <ActionButton
          label={formatEngagementCount(shareCount)}
          ariaLabel="Bagikan"
          onClick={handleShare}
        >
          <FiSend className="h-[33px] w-[33px]" />
        </ActionButton>
      </div>

      <div className="absolute inset-x-0 bottom-0 z-[1] space-y-3 px-4 pb-[calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+2rem)] pr-24 md:pb-5">
        <div className="flex min-w-0 items-center gap-3">
          <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-natalo-600 text-[13px] font-black text-white ring-1 ring-white/20">
            {isAdmin ? "NL" : post.author.name.charAt(0).toUpperCase()}
          </div>
          <div className="min-w-0">
            <p className="truncate text-[15px] font-extrabold leading-tight text-white">
              {isAdmin ? "Natalo Petshop" : post.author.name}
            </p>
            <p className="mt-1 line-clamp-2 text-[13px] font-medium leading-snug text-white/88">
              {post.description?.trim() || post.title}
              {isAdmin ? " 💙" : ""}
            </p>
          </div>
        </div>

        {product && (
          <button
            type="button"
            onClick={() => setProductSheetOpen(true)}
            className="flex max-w-full items-center gap-2 rounded-full border border-white/22 bg-black/22 px-3 py-2 text-left text-white shadow-sm shadow-black/10 backdrop-blur-xl transition active:scale-[0.98]"
          >
            <FiPackage className="h-4 w-4 shrink-0 text-white" />
            <span className="shrink-0 text-xs font-semibold text-white/90">
              {isCommunity ? "Produk digunakan" : "Produk terkait"}
            </span>
            <span className="truncate text-xs font-black text-natalo-300">
              {product.name}
            </span>
          </button>
        )}
      </div>

      {product && (
        <PinnedProductSheet
          open={productSheetOpen}
          product={product}
          isAdmin={isAdmin}
          onClose={() => setProductSheetOpen(false)}
        />
      )}
    </article>
  );
}

function ActionButton({
  children,
  label,
  ariaLabel,
  pressed,
  onClick,
}: {
  children: ReactNode;
  label: string;
  ariaLabel: string;
  pressed?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-label={ariaLabel}
      aria-pressed={pressed}
      onClick={onClick}
      className="flex min-h-11 min-w-11 flex-col items-center justify-center gap-1 text-[11px] font-semibold text-white drop-shadow-[0_2px_8px_rgba(0,0,0,0.75)] transition active:scale-95"
    >
      <span className="grid h-[34px] w-[34px] place-items-center">
        {children}
      </span>
      {label && <span className="leading-none">{label}</span>}
    </button>
  );
}

function PinnedProductSheet({
  open,
  product,
  isAdmin,
  onClose,
}: {
  open: boolean;
  product: NonNullable<FeedPostListItem["product"]>;
  isAdmin: boolean;
  onClose: () => void;
}) {
  const price = product.discountPrice ?? product.price;
  return (
    <BottomSheet open={open} onClose={onClose} title="Produk di Video">
      <div className="space-y-3">
        <Link
          href={`/products/${product.slug}`}
          className="flex items-center gap-3 rounded-2xl border border-gray-100 bg-white p-3 transition active:bg-gray-50"
        >
          {product.imageUrl ? (
            <div className="relative h-20 w-20 shrink-0 overflow-hidden rounded-2xl bg-gray-100">
              <Image
                src={product.imageUrl}
                alt={product.name}
                fill
                sizes="80px"
                placeholder="blur"
                blurDataURL={IMAGE_BLUR_GRAY}
                className="object-cover"
              />
            </div>
          ) : (
            <div className="grid h-20 w-20 shrink-0 place-items-center rounded-2xl bg-gray-100 text-natalo-600">
              <FiPackage className="h-7 w-7" />
            </div>
          )}
          <div className="min-w-0 flex-1">
            <p className="line-clamp-2 text-sm font-black text-gray-900">
              {product.name}
            </p>
            <p className="mt-1 text-base font-black text-natalo-600">
              {formatRupiah(price)}
            </p>
            <p className={`mt-1 text-xs font-bold ${product.stock > 0 ? "text-emerald-600" : "text-red-500"}`}>
              {product.stock > 0 ? `Stok ${product.stock}` : "Stok Habis"}
            </p>
          </div>
        </Link>
        <Link
          href={`/products/${product.slug}`}
          className="flex w-full items-center justify-center gap-2 rounded-full bg-natalo-600 py-3 text-sm font-black text-white transition active:scale-[0.98]"
        >
          <FiShoppingCart className="h-4 w-4" />
          {isAdmin ? "Beli Sekarang" : "Lihat Produk"}
        </Link>
      </div>
    </BottomSheet>
  );
}

function formatEngagementCount(count: number | null | undefined) {
  const safeCount = Number(count ?? 0);
  if (!Number.isFinite(safeCount) || safeCount <= 0) return "";
  if (safeCount >= 1_000_000) {
    return `${(safeCount / 1_000_000).toFixed(safeCount >= 10_000_000 ? 0 : 1).replace(/\.0$/, "")}M`;
  }
  if (safeCount >= 1_000) {
    return `${(safeCount / 1_000).toFixed(safeCount >= 10_000 ? 0 : 1).replace(/\.0$/, "")}K`;
  }
  return String(safeCount);
}
