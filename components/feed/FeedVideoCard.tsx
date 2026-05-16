"use client";

import Link from "next/link";
import Image from "next/image";
import type { ReactNode } from "react";
import { useEffect, useMemo, useState } from "react";
import {
  FiChevronRight,
  FiCheckCircle,
  FiPackage,
  FiShoppingBag,
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
  commentMode?: boolean;
  onOpenComments: (postId: string) => void;
};

export function FeedVideoCard({
  post,
  index,
  commentMode = false,
  onOpenComments,
}: Props) {
  const [liked, setLiked] = useState(post.viewerLiked);
  const [likeCount, setLikeCount] = useState(post.likeCount);
  const [likeBusy, setLikeBusy] = useState(false);
  const [shareCount, setShareCount] = useState(post.shareCount ?? 0);
  const [productSheetOpen, setProductSheetOpen] = useState(false);

  const isAdmin = post.author.role === "ADMIN";
  const product = post.product;
  // Shop the Look — daftar lengkap tagged products. Fallback ke single
  // `product` untuk legacy posts yang belum di-migrate ke FeedPostProduct.
  const taggedProducts = useMemo(() => {
    if (post.taggedProducts && post.taggedProducts.length > 0) {
      return post.taggedProducts;
    }
    if (product) {
      return [
        {
          id: product.id,
          slug: product.slug,
          name: product.name,
          price: product.price,
          discountPrice: product.discountPrice,
          stock: product.stock,
          imageUrl: product.imageUrl,
          position: 0,
          // Legacy single-product fallback — no per-product promo set.
          promoPrice: null,
        },
      ];
    }
    return [];
  }, [post.taggedProducts, product]);
  const hasMultipleProducts = taggedProducts.length > 1;
  const [carouselIndex, setCarouselIndex] = useState(0);
  const currentCarouselProduct = taggedProducts[carouselIndex] ?? null;
  const hasVideo = Boolean(post.videoUrl);
  const productHref = product ? `/products/${product.slug}` : "#";
  const creatorName = isAdmin ? "Natalo Petshop" : post.author.name;
  const caption = cleanFeedCaption(post.description, post.title);

  // Auto-rotate carousel — fade dari produk satu ke berikutnya tiap 4s.
  // Skip rotation kalau cuma 1 produk atau sheet lagi open (jangan
  // mengganggu user saat lihat detail).
  useEffect(() => {
    if (!hasMultipleProducts || productSheetOpen) return;
    const t = window.setInterval(() => {
      setCarouselIndex((i) => (i + 1) % taggedProducts.length);
    }, 4000);
    return () => window.clearInterval(t);
  }, [hasMultipleProducts, productSheetOpen, taggedProducts.length]);

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

  // Double-tap pada video: Instagram pattern — selalu SET liked=true, tidak
  // pernah unlike. Repeated double-tap hanya replay heart animation di
  // FeedVideoPlayer. Untuk unlike user harus klik tombol heart di rail.
  async function handleDoubleTapLike() {
    hapticTap();
    if (liked || likeBusy) return; // sudah liked atau lagi inflight — skip API call
    // Sama-sama optimistic update + POST seperti toggleLike, tapi tidak
    // pernah toggle ke false.
    setLikeBusy(true);
    setLiked(true);
    setLikeCount((prev) => prev + 1);
    try {
      const res = await fetch(`/api/feed/posts/${post.id}/like`, { method: "POST" });
      if (!res.ok) throw new Error("Like failed");
      const data: { liked: boolean; likeCount: number } = await res.json();
      setLiked(data.liked);
      setLikeCount(data.likeCount);
    } catch {
      // Revert optimistic update jika gagal.
      setLiked(false);
      setLikeCount((prev) => Math.max(0, prev - 1));
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

  const videoAspectRatio =
    post.videoWidth && post.videoHeight
      ? `${post.videoWidth} / ${post.videoHeight}`
      : "9 / 16";

  return (
    <article
      className={`relative min-h-full snap-start overflow-hidden bg-black text-white shadow-sm transition-colors duration-300 md:rounded-[28px] ${
        commentMode ? "z-[170]" : ""
      }`}
    >
      <div
        className={
          commentMode
            ? "absolute left-1/2 top-[calc(env(safe-area-inset-top)+18px)] z-[180] w-[min(88vw,410px)] -translate-x-1/2 overflow-hidden rounded-[22px] bg-black shadow-[0_22px_70px_rgba(0,0,0,0.55)] ring-1 ring-white/15 transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] md:w-[min(70vw,430px)]"
            : "absolute inset-x-0 top-0 overflow-hidden transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] [bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom))] md:bottom-0"
        }
        style={
          commentMode
            ? {
                aspectRatio: videoAspectRatio,
                height: "clamp(220px, 34dvh, 320px)",
              }
            : undefined
        }
      >
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
            // object-fit is decided inside FeedVideoPlayer (object-contain
            // for Reels-style letterbox so vertical video plays at its true
            // aspect ratio without crop). Don't force it back to cover here.
            className="h-full min-h-full rounded-none"
            onDoubleTap={handleDoubleTapLike}
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

      {/* Subtle gradient at the bottom for caption readability — Reels
          uses a much lighter gradient than TikTok because object-contain
          leaves the bottom edge of the video well clear of the caption. */}
      {!commentMode && (
        <div className="pointer-events-none absolute inset-x-0 bottom-0 z-[1] h-[220px] bg-gradient-to-t from-black/70 via-black/35 to-transparent" />
      )}

      {/* Right action rail — fixed grid: 30px icon + 16px count slot.
          Slot height tetap walau count = 0, supaya jarak vertical antar
          tombol identik di semua video (sebelumnya icon loncat naik kalau
          count kosong karena gap-1 tidak render). */}
      {!commentMode && (
        <div className="absolute right-3 z-[2] flex flex-col items-center gap-5 [bottom:calc(env(safe-area-inset-bottom)+200px)] md:bottom-10">
          <ActionButton
            label={formatEngagementCount(likeCount)}
            ariaLabel={liked ? "Batal suka" : "Suka"}
            pressed={liked}
            onClick={toggleLike}
          >
            <PetLikeIcon active={liked} />
          </ActionButton>
          <ActionButton
            label={formatEngagementCount(post.commentCount)}
            ariaLabel="Komentar"
            onClick={() => onOpenComments(post.id)}
          >
            <PetCommentIcon />
          </ActionButton>
          <ActionButton
            label={formatEngagementCount(shareCount)}
            ariaLabel="Bagikan"
            onClick={handleShare}
          >
            <PetShareIcon />
          </ActionButton>
        </div>
      )}

      {/* Bottom-left content: promo badge → product tag carousel → creator → caption */}
      {!commentMode && (
        <div className="absolute left-4 right-[76px] z-[2] [bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+1.5rem)] md:bottom-24">
          {/* PROMO badge — sync dengan carousel produk. Setiap tagged
              product punya promoPrice sendiri (set admin) yang dibanding
              ke product.price (harga katalog). Badge auto-switch saat
              carousel rotate ke produk berikutnya. Fallback ke legacy
              post.promo kalau current product belum di-set promoPrice.
              Tap → open product sheet untuk beli. */}
          {post.kind === "PROMO" &&
            (() => {
              // Resolve harga asli + diskon untuk produk yang sedang
              // di-display di carousel.
              let originalPrice: number | null = null;
              let discountPrice: number | null = null;
              if (
                currentCarouselProduct &&
                currentCarouselProduct.promoPrice != null &&
                currentCarouselProduct.promoPrice <
                  currentCarouselProduct.price
              ) {
                originalPrice = currentCarouselProduct.price;
                discountPrice = currentCarouselProduct.promoPrice;
              } else if (post.promo) {
                // Legacy single-price fallback untuk post lama yg belum
                // di-migrate ke per-product pricing.
                originalPrice = post.promo.originalPrice;
                discountPrice = post.promo.discountPrice;
              }
              if (originalPrice === null || discountPrice === null) return null;
              const off = Math.round(
                ((originalPrice - discountPrice) / originalPrice) * 100,
              );
              return (
                <button
                  type="button"
                  onClick={() => setProductSheetOpen(true)}
                  // Key by current product so React mounts ulang tiap
                  // rotation → animation re-trigger + visual cue ke user.
                  key={currentCarouselProduct?.id ?? "legacy"}
                  className="mb-2.5 flex w-full max-w-full items-stretch gap-0 overflow-hidden rounded-2xl bg-gradient-to-r from-red-600 to-rose-500 text-left text-white shadow-lg shadow-red-900/30 transition active:scale-[0.98]"
                  style={{
                    animation: hasMultipleProducts
                      ? "natalo-feed-product-fade 4000ms ease-in-out infinite"
                      : undefined,
                  }}
                >
                  <div className="grid place-items-center bg-white/15 px-2.5 py-2">
                    <span className="text-[10px] font-black uppercase tracking-wider">
                      Promo
                    </span>
                    <span className="text-base font-black leading-none">
                      {off}%
                    </span>
                    <span className="text-[9px] font-bold uppercase">Off</span>
                  </div>
                  <div className="flex min-w-0 flex-1 flex-col justify-center px-3 py-1.5">
                    <p className="truncate text-[11px] font-semibold text-white/85 line-through">
                      {formatRupiah(originalPrice)}
                    </p>
                    <p className="truncate text-base font-black leading-tight">
                      {formatRupiah(discountPrice)}
                    </p>
                  </div>
                  <div className="grid shrink-0 place-items-center bg-white/15 px-3 py-2">
                    <FiShoppingCart className="h-5 w-5" aria-hidden />
                    <span className="mt-0.5 text-[9px] font-black uppercase tracking-wide">
                      Beli
                    </span>
                  </div>
                </button>
              );
            })()}
          {currentCarouselProduct && (
            <button
              type="button"
              onClick={() => setProductSheetOpen(true)}
              className="mb-2.5 inline-flex h-10 max-w-full items-center gap-2 rounded-[14px] border border-[#D6A84A]/20 bg-black/[0.22] px-3 text-left text-white shadow-sm shadow-black/10 backdrop-blur-[14px] transition active:scale-[0.98]"
              key={currentCarouselProduct.id}
              style={{
                animation: hasMultipleProducts
                  ? "natalo-feed-product-fade 4000ms ease-in-out infinite"
                  : undefined,
              }}
            >
              <FiShoppingBag className="h-4 w-4 shrink-0 text-white/75" aria-hidden="true" />
              <span className="shrink-0 text-[12px] font-semibold text-white/90">
                {hasMultipleProducts
                  ? `${taggedProducts.length} produk`
                  : "Produk digunakan"}
              </span>
              <span className="min-w-0 truncate text-[12px] font-semibold text-white/85">
                {currentCarouselProduct.name}
              </span>
              <FiChevronRight className="h-4 w-4 shrink-0 text-white/65" aria-hidden="true" />
            </button>
          )}
          <div className="flex min-w-0 items-center gap-2">
            <p
              className={`truncate text-[17px] leading-tight drop-shadow-[0_1px_2px_rgba(0,0,0,0.5)] ${
                isAdmin
                  ? "font-bold text-[#D6A84A]"
                  : "font-semibold text-white"
              }`}
            >
              {creatorName}
            </p>
            {isAdmin && (
              <span className="inline-flex h-[22px] shrink-0 items-center gap-1 rounded-full border border-[#D6A84A]/35 bg-[#D6A84A]/15 px-2 text-[10.5px] font-semibold text-[#E8C878] backdrop-blur-[8px]">
                <FiCheckCircle className="h-3 w-3" aria-hidden="true" />
                Official
              </span>
            )}
          </div>
          {caption && (
            <p className="mt-1.5 line-clamp-2 text-[15px] font-normal leading-snug text-white drop-shadow-[0_1px_2px_rgba(0,0,0,0.5)]">
              {caption}
            </p>
          )}
        </div>
      )}

      {taggedProducts.length > 0 && (
        <PinnedProductSheet
          open={productSheetOpen}
          products={taggedProducts}
          isAdmin={isAdmin}
          onClose={() => setProductSheetOpen(false)}
        />
      )}

      <style>{`
        @keyframes natalo-feed-product-fade {
          0% { opacity: 0; transform: translateY(4px); }
          8% { opacity: 1; transform: translateY(0); }
          92% { opacity: 1; transform: translateY(0); }
          100% { opacity: 0; transform: translateY(-4px); }
        }
      `}</style>
    </article>
  );
}

function PetLikeIcon({ active }: { active?: boolean }) {
  return (
    <svg
      viewBox="0 0 36 36"
      className="h-8 w-8 overflow-visible"
      fill="none"
      aria-hidden="true"
    >
      <path
        d="M18 30.5S6.2 23.8 4.2 16.7C2.7 11.5 5.6 6.2 10.7 6.2c3 0 5.4 1.7 7.3 4.3 1.9-2.6 4.3-4.3 7.3-4.3 5.1 0 8 5.3 6.5 10.5C29.8 23.8 18 30.5 18 30.5Z"
        fill={active ? "#FF4D61" : "rgba(255,255,255,0.04)"}
        stroke={active ? "#FF4D61" : "currentColor"}
        strokeWidth="2.45"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <g fill={active ? "#fff" : "currentColor"} opacity={active ? 0.96 : 0.94}>
        <ellipse cx="18" cy="21.1" rx="4.1" ry="3.2" />
        <ellipse cx="13.5" cy="17.3" rx="1.65" ry="2.05" transform="rotate(-24 13.5 17.3)" />
        <ellipse cx="16.6" cy="15.3" rx="1.55" ry="2.05" transform="rotate(-8 16.6 15.3)" />
        <ellipse cx="19.4" cy="15.3" rx="1.55" ry="2.05" transform="rotate(8 19.4 15.3)" />
        <ellipse cx="22.5" cy="17.3" rx="1.65" ry="2.05" transform="rotate(24 22.5 17.3)" />
      </g>
    </svg>
  );
}

function PetCommentIcon() {
  return (
    <svg
      viewBox="0 0 36 36"
      className="h-8 w-8 overflow-visible"
      fill="none"
      aria-hidden="true"
    >
      <path
        d="M11.1 9.8 9.4 5.6 14.5 8M24.9 9.8l1.7-4.2L21.5 8"
        stroke="currentColor"
        strokeWidth="2.25"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M7.2 16.1c0-4.3 3.7-7.8 8.3-7.8h5c4.6 0 8.3 3.5 8.3 7.8v3.1c0 4.3-3.7 7.8-8.3 7.8h-3.6l-5.6 3.5c-.8.5-1.8-.2-1.6-1.1l.7-3.6c-2-1.4-3.2-3.8-3.2-6.6v-3.1Z"
        fill="rgba(255,255,255,0.04)"
        stroke="currentColor"
        strokeWidth="2.35"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <g fill="currentColor">
        <ellipse cx="18" cy="20.4" rx="2.75" ry="2.15" />
        <ellipse cx="14.7" cy="17.6" rx="1.05" ry="1.32" transform="rotate(-20 14.7 17.6)" />
        <ellipse cx="17" cy="16.3" rx="1" ry="1.3" transform="rotate(-6 17 16.3)" />
        <ellipse cx="19" cy="16.3" rx="1" ry="1.3" transform="rotate(6 19 16.3)" />
        <ellipse cx="21.3" cy="17.6" rx="1.05" ry="1.32" transform="rotate(20 21.3 17.6)" />
      </g>
    </svg>
  );
}

function PetShareIcon() {
  return (
    <svg
      viewBox="0 0 36 36"
      className="h-8 w-8 overflow-visible"
      fill="none"
      aria-hidden="true"
    >
      <path
        d="M5.4 17.6 30.4 6.9 22 29.5l-4.5-9.1-12.1-2.8Z"
        fill="rgba(255,255,255,0.04)"
        stroke="currentColor"
        strokeWidth="2.45"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M17.5 20.4 30.4 6.9"
        stroke="currentColor"
        strokeWidth="2.15"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <g fill="currentColor" opacity="0.94">
        <ellipse cx="8.6" cy="25.4" rx="1.75" ry="1.35" transform="rotate(-22 8.6 25.4)" />
        <ellipse cx="12.6" cy="28.2" rx="2.35" ry="1.7" transform="rotate(15 12.6 28.2)" />
        <circle cx="11.2" cy="23.8" r="1" />
        <circle cx="14.1" cy="24.7" r="0.95" />
      </g>
    </svg>
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
      // Fixed grid: icon-cell 32px + gap 4px + count-cell 16px = 52px
      // total. Count-cell tinggi tetap walau label kosong supaya tinggi
      // tombol identik di semua video (cegah icon Like loncat naik saat
      // count = 0 sementara Comment punya angka).
      className="flex min-w-[44px] flex-col items-center text-[12px] font-bold text-white drop-shadow-[0_1px_2px_rgba(0,0,0,0.55)] transition active:scale-95"
    >
      <span className="grid h-8 w-8 place-items-center">
        {children}
      </span>
      <span
        className="mt-1 h-[14px] leading-[14px] tabular-nums"
        aria-hidden={!label}
      >
        {label}
      </span>
    </button>
  );
}

type SheetProduct = NonNullable<FeedPostListItem["product"]> | FeedPostListItem["taggedProducts"][number];

function PinnedProductSheet({
  open,
  products,
  isAdmin,
  onClose,
}: {
  open: boolean;
  products: SheetProduct[];
  isAdmin: boolean;
  onClose: () => void;
}) {
  const title =
    products.length > 1
      ? `${products.length} Produk di Video`
      : "Produk di Video";
  return (
    <BottomSheet open={open} onClose={onClose} title={title} variant="dark">
      <div className="space-y-3">
        {products.map((product) => {
          // Priority: per-product promoPrice (kind=PROMO admin set) >
          // catalog discountPrice > base price. Kalau ada promoPrice
          // valid, tampilkan harga normal coret + badge diskon.
          const promoPrice =
            "promoPrice" in product && product.promoPrice != null
              ? product.promoPrice
              : null;
          const hasPromo = promoPrice != null && promoPrice < product.price;
          const displayPrice = hasPromo
            ? promoPrice
            : product.discountPrice ?? product.price;
          const showStrike = hasPromo;
          const discountPct = hasPromo
            ? Math.round(((product.price - promoPrice) / product.price) * 100)
            : 0;
          return (
            <Link
              key={product.id}
              href={`/products/${product.slug}`}
              className="flex items-center gap-3 rounded-2xl border border-[#242B33] bg-[#111820] p-3 transition hover:bg-[#151F2A] active:bg-[#172230]"
            >
              {product.imageUrl ? (
                <div className="relative h-20 w-20 shrink-0 overflow-hidden rounded-2xl bg-white">
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
                <div className="grid h-20 w-20 shrink-0 place-items-center rounded-2xl bg-white/[0.08] text-natalo-300">
                  <FiPackage className="h-7 w-7" />
                </div>
              )}
              <div className="min-w-0 flex-1">
                <p className="line-clamp-2 text-sm font-black text-white">
                  {product.name}
                </p>
                <div className="mt-1 flex items-baseline gap-2">
                  <p className="text-base font-black text-natalo-300">
                    {formatRupiah(displayPrice)}
                  </p>
                  {showStrike && (
                    <>
                      <span className="text-xs font-semibold text-zinc-500 line-through">
                        {formatRupiah(product.price)}
                      </span>
                      <span className="rounded-full bg-red-500/20 px-2 py-0.5 text-[10px] font-black text-red-300">
                        -{discountPct}%
                      </span>
                    </>
                  )}
                </div>
                <p
                  className={`mt-1 text-xs font-bold ${product.stock > 0 ? "text-emerald-400" : "text-red-400"}`}
                >
                  {product.stock > 0 ? `Stok ${product.stock}` : "Stok Habis"}
                </p>
              </div>
              <FiChevronRight className="h-5 w-5 shrink-0 text-zinc-300" aria-hidden />
            </Link>
          );
        })}
        {/* CTA umum — kalau cuma 1 produk, langsung "Lihat / Beli" dengan
            slug yang spesifik. Kalau multi, anchor scroll back ke list di atas. */}
        {products.length === 1 && (
          <Link
            href={`/products/${products[0].slug}`}
            className="flex w-full items-center justify-center gap-2 rounded-full bg-natalo-600 py-3 text-sm font-black text-white transition active:scale-[0.98]"
          >
            <FiShoppingCart className="h-4 w-4" />
            {isAdmin ? "Beli Sekarang" : "Lihat Produk"}
          </Link>
        )}
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

function cleanFeedCaption(description: string | null, title: string) {
  const raw = (description?.trim() || title || "").trim();
  if (!raw) return "";

  return raw
    .split(/\n+/)
    .map((line) => line.trim())
    .filter((line) => line && !/^info peliharaan\s*:/i.test(line))
    .join("\n")
    .replace(/\s*info peliharaan\s*:\s*(cat|dog|other|kucing|anjing|lainnya)\s*$/i, "")
    .trim();
}
