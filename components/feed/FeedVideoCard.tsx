"use client";

import Link from "next/link";
import Image from "next/image";
import type { ReactNode } from "react";
import { useState } from "react";
import {
  FiHeart,
  FiMessageCircle,
  FiPackage,
  FiShare2,
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
  onOpenComments: (postId: string) => void;
};

export function FeedVideoCard({ post, onOpenComments }: Props) {
  const [liked, setLiked] = useState(post.viewerLiked);
  const [likeCount, setLikeCount] = useState(post.likeCount);
  const [likeBusy, setLikeBusy] = useState(false);
  const [productSheetOpen, setProductSheetOpen] = useState(false);

  const isAdmin = post.author.role === "ADMIN";
  const product = post.product;
  const promo = post.promo;
  const hasVideo = Boolean(post.videoUrl);
  const isCommunity = post.kind === "COMMUNITY";
  const contentLabel = getContentLabel(post.kind);
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
    await shareContent({
      title: post.title,
      text: post.description ?? "Lihat video Natalo Petshop ini.",
      url,
    });
  }

  return (
    <article className="relative min-h-full snap-start overflow-hidden bg-black text-white shadow-sm md:rounded-[28px]">
      <div className="absolute inset-0">
        {hasVideo && post.videoUrl ? (
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

      <div className="absolute bottom-[calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+2.25rem)] right-4 z-[2] flex flex-col items-center gap-4 md:bottom-5">
        <ActionButton
          label={String(likeCount)}
          ariaLabel={liked ? "Batal suka" : "Suka"}
          pressed={liked}
          onClick={toggleLike}
        >
          <FiHeart className={`h-8 w-8 ${liked ? "fill-red-500 stroke-red-500" : ""}`} />
        </ActionButton>
        <ActionButton
          label={String(post.commentCount)}
          ariaLabel="Komentar"
          onClick={() => onOpenComments(post.id)}
        >
          <FiMessageCircle className="h-8 w-8" />
        </ActionButton>
        <ActionButton label="" ariaLabel="Bagikan" onClick={handleShare}>
          <FiShare2 className="h-8 w-8" />
        </ActionButton>
      </div>

      <div className="absolute inset-x-0 bottom-0 z-[1] space-y-3 px-4 pb-[calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+2.25rem)] pr-24 md:pb-5">
        <div className="min-w-0">
          <p className="flex min-w-0 items-center gap-1.5 text-sm font-black text-white">
            <span className="min-w-0 truncate">
              {isAdmin ? "Natalo Petshop" : post.author.name}
            </span>
            {isAdmin && (
              <span className="shrink-0 rounded-full border border-white/20 bg-white/15 px-1.5 py-0.5 text-[9px] font-black uppercase text-white backdrop-blur-xl">
                Official
              </span>
            )}
            {!isAdmin && product && (
              <span className="shrink-0 rounded-full border border-white/20 bg-white/15 px-1.5 py-0.5 text-[9px] font-black uppercase text-white backdrop-blur-xl">
                Pembeli Terverifikasi
              </span>
            )}
          </p>
          <p className="text-[11px] font-semibold text-white/70">
            {formatRelativeTime(post.publishedAt ?? post.createdAt)}
          </p>
        </div>

        <div className="flex flex-wrap gap-1.5">
          <span className={`rounded-full border border-white/25 px-2 py-1 text-[10px] font-black uppercase shadow-sm shadow-black/10 backdrop-blur-xl ${contentLabel.className}`}>
            {contentLabel.label}
          </span>
          {promo && (
            <span className="rounded-full border border-white/25 bg-white/20 px-2 py-1 text-[10px] font-black uppercase text-white shadow-sm shadow-black/10 backdrop-blur-xl">
              Promo
            </span>
          )}
        </div>

        <div>
          <h2 className="line-clamp-2 text-base font-black leading-snug text-white">
            {post.title}
          </h2>
          {post.description && (
            <p className="mt-1 line-clamp-3 text-xs leading-relaxed text-white/85">
              {post.description}
            </p>
          )}
        </div>

        {promo && (
          <div className="inline-flex items-baseline gap-2 rounded-2xl border border-white/25 bg-white/18 px-3 py-2 text-left text-white shadow-sm shadow-black/10 backdrop-blur-xl">
            <span className="text-base font-black">
              {formatRupiah(promo.discountPrice)}
            </span>
            <span className="text-xs text-white/60 line-through">
              {formatRupiah(promo.originalPrice)}
            </span>
          </div>
        )}

        {product && (
          <button
            type="button"
            onClick={() => setProductSheetOpen(true)}
            className="flex max-w-full items-center gap-2 rounded-full border border-white/25 bg-white/18 px-3 py-2 text-left text-white shadow-sm shadow-black/10 backdrop-blur-xl transition active:scale-[0.98]"
          >
            <FiPackage className="h-4 w-4 shrink-0 text-white" />
            <span className="truncate text-xs font-black">
              {isCommunity ? "Produk dipakai" : "Lihat produk"} - {product.name}
            </span>
          </button>
        )}

        {isAdmin && product && product.stock > 0 && (
          <Link
            href={productHref}
            className="inline-flex items-center gap-2 rounded-full border border-white/25 bg-white/18 px-4 py-2.5 text-sm font-black text-white shadow-lg shadow-black/10 backdrop-blur-xl transition active:scale-[0.98]"
          >
            <FiShoppingCart className="h-4 w-4" />
            Beli Sekarang
          </Link>
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
      className="flex min-h-11 min-w-11 flex-col items-center justify-center gap-1 text-[11px] font-black text-white drop-shadow-[0_2px_8px_rgba(0,0,0,0.75)] transition active:scale-95"
    >
      <span className="grid h-8 w-8 place-items-center">
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

function getContentLabel(kind: FeedPostListItem["kind"]) {
  if (kind === "PROMO") {
    return { label: "Promo", className: "bg-white/20 text-white" };
  }
  if (kind === "PRODUCT_ONLY" || kind === "VIDEO_PRODUCT") {
    return { label: "Jualan Produk", className: "bg-white/20 text-white" };
  }
  if (kind === "VIDEO_ONLY") {
    return { label: "Edukasi", className: "bg-white/20 text-white" };
  }
  return { label: "Komunitas", className: "bg-white/20 text-white" };
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
  return d.toLocaleDateString("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}
