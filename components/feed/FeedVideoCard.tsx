"use client";

import Link from "next/link";
import Image from "next/image";
import type { ReactNode } from "react";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  FiChevronRight,
  FiCheckCircle,
  FiPackage,
  FiShoppingBag,
  FiShoppingCart,
} from "react-icons/fi";
import { BottomSheet } from "@/components/BottomSheet";
import { addItemToCart } from "@/lib/cart-actions";
import { loadCart, type CartItem } from "@/lib/cart";
import { formatRupiah } from "@/lib/format";
import { hapticTap } from "@/lib/native/haptics";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import { shareContent } from "@/lib/share";
import type { FeedPostListItem } from "@/lib/feed/types";
import { FeedVideoPlayer } from "./FeedVideoPlayer";
import { FeedCreatorInfo } from "./FeedCreatorInfo";

const CHECKOUT_SELECTION_KEY = "checkout:selectedCartItems";

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
  const [cartSheetOpen, setCartSheetOpen] = useState(false);
  const [cartQuantityCount, setCartQuantityCount] = useState(0);

  const isAdmin = post.author.role === "ADMIN";
  const product = post.product;
  // Shop the Look — daftar lengkap tagged products. Fallback ke single
  // `product` untuk legacy posts yang belum di-migrate ke FeedPostProduct.
  const taggedProducts = useMemo(() => {
    if (post.taggedProducts && post.taggedProducts.length > 0) {
      return post.taggedProducts.slice(0, 5);
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
          weightGram: product.weightGram,
          isAvailable: product.isAvailable,
          imageUrl: product.imageUrl,
          position: 0,
          // Legacy single-product fallback — no per-product promo set.
          promoPrice: null,
          hasVariants: product.hasVariants,
          avgRating: product.avgRating,
          reviewCount: product.reviewCount,
          soldCount: product.soldCount,
        },
      ];
    }
    return [];
  }, [post.taggedProducts, product]);
  const hasMultipleProducts = taggedProducts.length > 1;
  const currentCarouselProduct = taggedProducts[0] ?? null;
  const productPillPromo = taggedProducts
    .map((item) => getFeedProductPricing(item, post.promo))
    .find((pricing) => pricing.hasPromo && pricing.discountPct > 0);
  const productSummary =
    hasMultipleProducts && taggedProducts.length > 0
      ? `${taggedProducts
          .slice(0, 2)
          .map((item) => item.name)
          .join(", ")}${taggedProducts.length > 2 ? ", ..." : ""}`
      : currentCarouselProduct?.name;
  const hasVideo = Boolean(post.videoUrl);
  const productHref = product ? `/products/${product.slug}` : "#";
  const creatorName = isAdmin ? "Natalo Petshop" : post.author.name;
  const creatorProfilePhotoUrl =
    post.author.profilePhotoUrl ?? post.author.avatarUrl ?? null;
  const caption = cleanFeedCaption(post.description, post.title);

  useEffect(() => {
    function syncCartCount() {
      setCartQuantityCount(
        loadCart().reduce((sum, item) => sum + Math.max(0, item.quantity), 0),
      );
    }

    syncCartCount();
    window.addEventListener("cart-updated", syncCartCount);
    return () => window.removeEventListener("cart-updated", syncCartCount);
  }, []);

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

  /**
   * Quick add to cart langsung dari pill Shop the Look — 1 tap tanpa
   * buka sheet. Hanya valid untuk produk yang TIDAK punya variants
   * (single SKU, no size/color picker needed).
   *
   * Untuk produk dengan variants: tap "+" jatuh ke sheet supaya user
   * pilih variant dulu — tanpa variant, addItemToCart akan tambah
   * parent product ID yang tidak valid di checkout (item tidak match
   * SKU). UX-nya lebih jelek dibanding extra tap untuk open sheet.
   *
   * Stop propagation supaya pill onClick (yg buka sheet) tidak juga
   * fire — quick add dan open sheet harus mutually exclusive di tap.
   */
  function handleQuickAddCurrent(e: React.MouseEvent) {
    e.stopPropagation();
    if (!currentCarouselProduct) return;
    if (!currentCarouselProduct.isAvailable || currentCarouselProduct.stock <= 0) {
      return;
    }
    // Produk multi-variant: tidak boleh quick add — open sheet supaya
    // user pilih variant di sana (atau navigate ke PDP via tap detail).
    if (currentCarouselProduct.hasVariants) {
      setProductSheetOpen(true);
      return;
    }
    hapticTap();
    const pricing = getFeedProductPricing(currentCarouselProduct, post.promo);
    const cartItem = buildFeedCartItem(
      currentCarouselProduct,
      pricing.displayPrice,
    );
    addItemToCart(cartItem, {
      successMessage: `${currentCarouselProduct.name} masuk keranjang`,
    });
  }

  const videoAspectRatio =
    post.videoWidth && post.videoHeight
      ? `${post.videoWidth} / ${post.videoHeight}`
      : "9 / 16";

  return (
    <article
      className={`relative min-h-full snap-start overflow-hidden bg-black text-white shadow-sm transition-colors duration-300 md:rounded-[28px] ${
        commentMode ? "z-[9005]" : ""
      }`}
    >
      <div
        data-feed-comment-video-preview={commentMode ? "true" : undefined}
        className={
          commentMode
            ? "absolute left-1/2 top-[calc(env(safe-area-inset-top)+18px)] z-[180] overflow-hidden rounded-[22px] bg-black shadow-[0_22px_70px_rgba(0,0,0,0.55)] ring-1 ring-white/15 transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)]"
            : "absolute inset-x-0 top-0 overflow-hidden transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] [bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom))] md:bottom-0"
        }
        style={
          commentMode
            ? {
                aspectRatio: videoAspectRatio,
                height: "clamp(220px, 34dvh, 320px)",
                transform:
                  "translateX(-50%) translateY(var(--comment-video-y, 0px)) scale(var(--comment-video-scale, 1))",
                transformOrigin: "top center",
                width: "min(88vw, 410px)",
                willChange: "transform, border-radius",
              }
            : {
                borderRadius: "0px",
                transform: "none",
                willChange: "auto",
              }
        }
      >
        {hasVideo && post.videoUrl ? (
          <FeedVideoPlayer
            postId={post.id}
            index={index}
            videoUrl={post.videoUrl}
            thumbnailUrl={post.thumbnailUrl}
            thumbnailBlurhash={post.thumbnailBlurhash}
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

      {/* Right action rail — compact Reels-style icon + count stack.
          Slot height tetap walau count = 0, supaya jarak vertical antar
          tombol identik di semua video (sebelumnya icon loncat naik kalau
          count kosong karena gap-1 tidak render). */}
      {!commentMode && (
        <div className="absolute right-3.5 z-[2] flex flex-col items-center gap-[18px] [bottom:calc(env(safe-area-inset-bottom)+168px)] md:bottom-8">
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
          {/* Keranjang Feed — buka cart sebagai bottom sheet dark supaya
              user bisa cek isi keranjang tanpa meninggalkan Feed. */}
          <ActionButton
            label={formatEngagementCount(cartQuantityCount)}
            ariaLabel="Lihat keranjang"
            onClick={() => setCartSheetOpen(true)}
          >
            <PetShopBagIcon />
          </ActionButton>
        </div>
      )}

      {/* Bottom-left content: compact product pill → creator → caption */}
      {!commentMode && (
        <div className="absolute left-4 right-[76px] z-[2] [bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+1.5rem)] md:bottom-24">
          {currentCarouselProduct && (
            // Pill split jadi 2 area: kiri (info + chevron) buka sheet,
            // kanan (+ Cart) quick add. Bukan single button supaya nested
            // <button> tidak invalid HTML.
            <div
              className="mb-2.5 inline-flex h-10 max-w-full items-center rounded-[16px] border border-white/15 bg-black/[0.24] text-white shadow-sm shadow-black/10 backdrop-blur-[16px]"
              key={currentCarouselProduct.id}
            >
              <button
                type="button"
                onClick={() => setProductSheetOpen(true)}
                className="flex h-full min-w-0 flex-1 items-center gap-2 rounded-l-[16px] px-3 text-left transition active:scale-[0.98]"
                aria-label={
                  hasMultipleProducts
                    ? `Lihat ${taggedProducts.length} produk di video`
                    : `Lihat detail ${currentCarouselProduct.name}`
                }
              >
                <FiShoppingBag className="h-4 w-4 shrink-0 text-white/75" aria-hidden="true" />
                {hasMultipleProducts && (
                  <span className="hidden shrink-0 -space-x-1 sm:flex" aria-hidden="true">
                    {taggedProducts.slice(0, 3).map((item) => (
                      <span
                        key={item.id}
                        className="relative block h-5 w-5 overflow-hidden rounded-full border border-white/20 bg-white/10"
                      >
                        {item.imageUrl ? (
                          <Image
                            src={item.imageUrl}
                            alt=""
                            fill
                            sizes="20px"
                            placeholder="blur"
                            blurDataURL={IMAGE_BLUR_GRAY}
                            className="object-cover"
                          />
                        ) : (
                          <span className="grid h-full w-full place-items-center">
                            <FiPackage className="h-2.5 w-2.5 text-white/60" />
                          </span>
                        )}
                      </span>
                    ))}
                  </span>
                )}
                <span className="shrink-0 text-[12px] font-semibold text-white/90">
                  {hasMultipleProducts
                    ? `${taggedProducts.length} produk`
                    : "Produk digunakan"}
                </span>
                <span className="min-w-0 truncate text-[12px] font-semibold text-white/85">
                  {productSummary}
                </span>
                {productPillPromo && (
                  <span className="shrink-0 rounded-full bg-rose-500/85 px-2 py-0.5 text-[10px] font-black leading-none text-white shadow-sm shadow-rose-950/25">
                    PROMO {productPillPromo.discountPct}%
                  </span>
                )}
              </button>
              {/* Quick "+1 Cart" — direct tap tanpa buka sheet untuk
                  produk no-variant. Multi-variant fall back ke sheet
                  supaya user pilih varian dulu (handler check sendiri). */}
              <button
                type="button"
                onClick={handleQuickAddCurrent}
                disabled={
                  !currentCarouselProduct.isAvailable ||
                  currentCarouselProduct.stock <= 0
                }
                aria-label={`Tambah ${currentCarouselProduct.name} ke keranjang`}
                className="grid h-full w-10 shrink-0 place-items-center rounded-r-[16px] border-l border-white/15 text-white/90 transition active:scale-95 active:bg-white/5 disabled:cursor-not-allowed disabled:text-white/25"
              >
                <FiShoppingCart
                  className="h-4 w-4"
                  aria-hidden="true"
                />
              </button>
            </div>
          )}
          <FeedCreatorInfo
            userId={post.author.id}
            userName={creatorName}
            profilePhotoUrl={creatorProfilePhotoUrl}
            isOfficial={isAdmin}
            caption={caption}
            onCaptionClick={() => onOpenComments(post.id)}
            officialBadge={
              isAdmin ? (
                <span className="inline-flex h-[22px] shrink-0 items-center gap-1 rounded-full border border-[#D6A84A]/35 bg-[#D6A84A]/15 px-2 text-[10.5px] font-semibold text-[#E8C878] backdrop-blur-[8px]">
                  <FiCheckCircle className="h-3 w-3" aria-hidden="true" />
                  Official
                </span>
              ) : null
            }
          />
        </div>
      )}

      {taggedProducts.length > 0 && (
        <PinnedProductSheet
          open={productSheetOpen}
          products={taggedProducts}
          legacyPromo={post.promo}
          onClose={() => setProductSheetOpen(false)}
        />
      )}
      <FeedCartSheet
        open={cartSheetOpen}
        onClose={() => setCartSheetOpen(false)}
      />
    </article>
  );
}

function PetLikeIcon({ active }: { active?: boolean }) {
  return (
    <svg
      viewBox="0 0 36 36"
      className="h-[30px] w-[30px] overflow-visible"
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
      className="h-[30px] w-[30px] overflow-visible"
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
      className="h-[30px] w-[30px] overflow-visible"
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

function PetShopBagIcon() {
  // Stroked bag icon dengan rounded handles + cat-ear silhouette di body
  // supaya match playful theme Natalo Petshop. Same stroke weight 2.45px
  // dengan PetShareIcon supaya visual rail konsisten.
  return (
    <svg
      viewBox="0 0 36 36"
      className="h-[30px] w-[30px] overflow-visible"
      fill="none"
      aria-hidden="true"
    >
      {/* Bag body */}
      <path
        d="M8 12h20l-1.6 17.4a2 2 0 0 1-2 1.85H11.6a2 2 0 0 1-2-1.85L8 12Z"
        fill="rgba(255,255,255,0.04)"
        stroke="currentColor"
        strokeWidth="2.45"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {/* Handle — semicircle */}
      <path
        d="M13 12V9a5 5 0 0 1 10 0v3"
        stroke="currentColor"
        strokeWidth="2.15"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {/* Tiny paw dot di body supaya playful */}
      <g fill="currentColor" opacity="0.92">
        <circle cx="18" cy="20" r="1.25" />
        <circle cx="15.4" cy="22.4" r="0.85" />
        <circle cx="20.6" cy="22.4" r="0.85" />
        <ellipse cx="18" cy="24.4" rx="1.45" ry="1.05" />
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
      // Fixed grid: icon-cell 30px + gap 4px + count-cell 14px = 48px total.
      // Count-cell tinggi tetap walau label kosong supaya tinggi
      // tombol identik di semua video (cegah icon Like loncat naik saat
      // count = 0 sementara Comment punya angka).
      className="flex min-h-[46px] min-w-[46px] flex-col items-center text-[13px] font-bold text-white drop-shadow-[0_1px_2px_rgba(0,0,0,0.55)] transition active:scale-95"
    >
      <span className="grid h-[30px] w-[30px] place-items-center">
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
type LegacyPromo = FeedPostListItem["promo"];

function getFeedProductPricing(product: SheetProduct, legacyPromo?: LegacyPromo) {
  let originalPrice = product.price;
  let displayPrice = product.price;

  if (product.discountPrice != null && product.discountPrice > 0 && product.discountPrice < product.price) {
    displayPrice = product.discountPrice;
  }

  const promoPrice =
    "promoPrice" in product && product.promoPrice != null
      ? product.promoPrice
      : null;

  if (promoPrice != null && promoPrice > 0 && promoPrice < product.price) {
    displayPrice = promoPrice;
  } else if (
    legacyPromo &&
    legacyPromo.discountPrice > 0 &&
    legacyPromo.discountPrice < legacyPromo.originalPrice
  ) {
    originalPrice = legacyPromo.originalPrice;
    displayPrice = legacyPromo.discountPrice;
  }

  const hasPromo = displayPrice < originalPrice;
  const discountPct = hasPromo
    ? Math.max(1, Math.round(((originalPrice - displayPrice) / originalPrice) * 100))
    : 0;

  return { originalPrice, displayPrice, hasPromo, discountPct };
}

function buildFeedCartItem(
  product: SheetProduct,
  price: number,
  quantity: number = 1,
): CartItem {
  return {
    productId: product.id,
    slug: product.slug,
    variantId: null,
    variantLabel: null,
    name: product.name,
    price,
    quantity,
    subtotal: price * quantity,
    weightGram: product.weightGram,
    imageUrl: product.imageUrl,
    stock: product.stock,
  };
}

function cartSelectionKey(item: CartItem) {
  return `${item.productId}:${item.variantId ?? ""}`;
}

function withCartSubtotal(item: CartItem): CartItem {
  return {
    ...item,
    subtotal: item.price * item.quantity,
  };
}

function FeedCartSheet({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  const router = useRouter();
  const [cartItems, setCartItems] = useState<CartItem[]>([]);

  useEffect(() => {
    if (!open) return;

    function syncCartItems() {
      setCartItems(loadCart().map(withCartSubtotal));
    }

    syncCartItems();
    window.addEventListener("cart-updated", syncCartItems);
    return () => window.removeEventListener("cart-updated", syncCartItems);
  }, [open]);

  const itemCount = cartItems.reduce((sum, item) => sum + item.quantity, 0);
  const subtotal = cartItems.reduce(
    (sum, item) => sum + item.price * item.quantity,
    0,
  );

  function handleCheckoutFromFeed() {
    if (cartItems.length === 0) return;
    hapticTap();
    const checkoutItems = cartItems.map(withCartSubtotal);
    const cartKeys = checkoutItems.map(cartSelectionKey);

    try {
      sessionStorage.setItem(CHECKOUT_SELECTION_KEY, JSON.stringify(checkoutItems));
    } catch {
      // Checkout tetap bisa membaca dari cart lokal kalau sessionStorage gagal.
    }

    onClose();
    router.push(
      `/checkout?cart_item_ids=${encodeURIComponent(cartKeys.join(","))}&returnTo=${encodeURIComponent("/feed")}`,
    );
  }

  return (
    <BottomSheet
      open={open}
      onClose={onClose}
      title="Keranjang"
      variant="dark"
      footer={
        <div className="space-y-3">
          <div className="flex items-center justify-between gap-4 text-sm">
            <span className="font-semibold text-zinc-400">
              {itemCount > 0 ? `${itemCount} item` : "Keranjang kosong"}
            </span>
            <span className="text-lg font-black text-white">
              {formatRupiah(subtotal)}
            </span>
          </div>
          <button
            type="button"
            onClick={handleCheckoutFromFeed}
            disabled={cartItems.length === 0}
            className="relative flex h-12 w-full items-center justify-center overflow-hidden rounded-full border border-sky-200/55 bg-[linear-gradient(180deg,rgba(95,191,255,0.96)_0%,rgba(30,135,255,0.94)_44%,rgba(18,97,218,0.96)_100%)] px-5 text-sm font-black text-white shadow-[0_0_24px_rgba(57,154,255,0.38),0_10px_24px_rgba(0,83,189,0.3),inset_0_1px_0_rgba(255,255,255,0.55)] transition active:scale-[0.98] disabled:cursor-not-allowed disabled:border-white/8 disabled:bg-none disabled:bg-zinc-700 disabled:text-zinc-400 disabled:shadow-none disabled:active:scale-100"
          >
            <span className="pointer-events-none absolute inset-x-6 top-1 h-3 rounded-full bg-white/30 blur-[5px]" />
            <span className="relative">Checkout</span>
          </button>
        </div>
      }
    >
      {cartItems.length === 0 ? (
        <div className="rounded-3xl border border-white/10 bg-white/[0.04] px-4 py-8 text-center">
          <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-white/[0.06] text-natalo-300">
            <FiShoppingCart className="h-7 w-7" aria-hidden="true" />
          </div>
          <p className="mt-4 text-sm font-black text-white">
            Keranjang masih kosong
          </p>
          <p className="mt-1 text-xs leading-5 text-zinc-400">
            Tambahkan produk dari video Natalo, lalu checkout dari sini tanpa keluar dari Feed.
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          <p className="text-xs font-semibold text-zinc-400">
            Cek isi keranjang tanpa meninggalkan Feed.
          </p>
          {cartItems.map((item) => (
            <div
              key={cartSelectionKey(item)}
              className="flex items-center gap-3 rounded-2xl border border-[#242B33] bg-[#111820] p-3 shadow-[0_10px_28px_rgba(0,0,0,0.18)]"
            >
              <div className="relative h-16 w-16 shrink-0 overflow-hidden rounded-2xl bg-white/[0.08]">
                {item.imageUrl ? (
                  <Image
                    src={item.imageUrl}
                    alt={item.name}
                    fill
                    sizes="64px"
                    placeholder="blur"
                    blurDataURL={IMAGE_BLUR_GRAY}
                    className="object-cover"
                  />
                ) : (
                  <span className="grid h-full w-full place-items-center text-natalo-300">
                    <FiPackage className="h-6 w-6" />
                  </span>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <p className="line-clamp-2 text-sm font-black leading-snug text-white">
                  {item.name}
                </p>
                {item.variantLabel && (
                  <p className="mt-0.5 truncate text-xs font-semibold text-zinc-400">
                    {item.variantLabel}
                  </p>
                )}
                <div className="mt-1 flex items-center justify-between gap-3">
                  <span className="text-xs font-semibold text-zinc-400">
                    {item.quantity} x {formatRupiah(item.price)}
                  </span>
                  <span className="shrink-0 text-sm font-black text-natalo-300">
                    {formatRupiah(item.price * item.quantity)}
                  </span>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </BottomSheet>
  );
}

function PinnedProductSheet({
  open,
  products,
  legacyPromo,
  onClose,
}: {
  open: boolean;
  products: SheetProduct[];
  legacyPromo: LegacyPromo;
  onClose: () => void;
}) {
  const router = useRouter();

  function handleAddProduct(
    product: SheetProduct,
    quantity: number,
    redirectToCheckout = false,
  ) {
    if (!product.isAvailable || product.stock <= 0) return;
    // Multi-variant product: tidak boleh add-to-cart langsung di feed —
    // server tolak checkout tanpa variantId match. Redirect ke PDP supaya
    // user pilih varian dulu.
    if (product.hasVariants) {
      onClose();
      router.push(`/products/${product.slug}`);
      return;
    }
    hapticTap();

    const pricing = getFeedProductPricing(product, legacyPromo);
    const cartItem = buildFeedCartItem(product, pricing.displayPrice, quantity);
    const result = addItemToCart(cartItem, {
      showToast: !redirectToCheckout,
      successMessage:
        quantity > 1
          ? `${quantity}× ${product.name} masuk keranjang`
          : `${product.name} masuk keranjang`,
    });

    if (!result.ok || !redirectToCheckout) return;

    const cartKey = `${product.id}:`;
    try {
      sessionStorage.setItem(
        CHECKOUT_SELECTION_KEY,
        JSON.stringify([
          { ...cartItem, quantity, subtotal: pricing.displayPrice * quantity },
        ]),
      );
    } catch {
      // Checkout masih bisa membaca item dari cart lokal kalau sessionStorage gagal.
    }

    onClose();
    router.push(
      `/checkout?cart_item_ids=${encodeURIComponent(cartKey)}&returnTo=${encodeURIComponent("/feed")}`,
    );
  }

  return (
    <BottomSheet open={open} onClose={onClose} title="Produk di Video" variant="dark">
      <div className="space-y-3">
        {products.length > 1 && (
          <p className="text-xs font-semibold text-zinc-400">
            {products.length} produk ditag di video ini.
          </p>
        )}
        {products.map((product) => (
          <PinnedProductSheetCard
            key={product.id}
            product={product}
            legacyPromo={legacyPromo}
            onAdd={(qty) => handleAddProduct(product, qty, false)}
            onBuy={(qty) => handleAddProduct(product, qty, true)}
          />
        ))}
      </div>
    </BottomSheet>
  );
}

function PinnedProductSheetCard({
  product,
  legacyPromo,
  onAdd,
  onBuy,
}: {
  product: SheetProduct;
  legacyPromo: LegacyPromo;
  onAdd: (quantity: number) => void;
  onBuy: (quantity: number) => void;
}) {
  // Quantity stepper state per-card. Default 1. Max = product.stock supaya
  // user tidak overcommit (cart action sendiri juga cap stock, tapi UI
  // lebih jelas kalau button "-" disabled saat 1, "+" disabled saat
  // mencapai stock).
  const [quantity, setQuantity] = useState(1);
  const maxQty = Math.max(1, product.stock);

  function decQty() {
    setQuantity((q) => Math.max(1, q - 1));
  }
  function incQty() {
    setQuantity((q) => Math.min(maxQty, q + 1));
  }

  const pricing = getFeedProductPricing(product, legacyPromo);
  const unavailable = !product.isAvailable || product.stock <= 0;

  return (
    <div className="rounded-2xl border border-[#242B33] bg-[#111820] p-3 shadow-[0_10px_28px_rgba(0,0,0,0.18)]">
      <div className="flex items-center gap-3">
        <Link
          href={`/products/${product.slug}`}
          className="relative h-20 w-20 shrink-0 overflow-hidden rounded-2xl bg-white transition active:scale-[0.98]"
          aria-label={`Buka detail ${product.name}`}
        >
          {product.imageUrl ? (
            <Image
              src={product.imageUrl}
              alt={product.name}
              fill
              sizes="80px"
              placeholder="blur"
              blurDataURL={IMAGE_BLUR_GRAY}
              className="object-cover"
            />
          ) : (
            <span className="grid h-full w-full place-items-center bg-white/[0.08] text-natalo-300">
              <FiPackage className="h-7 w-7" />
            </span>
          )}
        </Link>

        <Link
          href={`/products/${product.slug}`}
          className="min-w-0 flex-1 transition active:opacity-80"
        >
          <div className="flex items-start gap-2">
            <p className="line-clamp-2 flex-1 text-sm font-black leading-snug text-white">
              {product.name}
            </p>
            <FiChevronRight className="mt-0.5 h-5 w-5 shrink-0 text-zinc-400" aria-hidden />
          </div>
          <div className="mt-1 flex flex-wrap items-baseline gap-2">
            <p className="text-base font-black text-natalo-300">
              {formatRupiah(pricing.displayPrice)}
            </p>
            {pricing.hasPromo && (
              <>
                <span className="text-xs font-semibold text-zinc-500 line-through">
                  {formatRupiah(pricing.originalPrice)}
                </span>
                <span className="rounded-full bg-rose-500/18 px-2 py-0.5 text-[10px] font-black text-rose-200 ring-1 ring-rose-400/25">
                  PROMO {pricing.discountPct}%
                </span>
              </>
            )}
          </div>
          <p
            className={`mt-1 text-xs font-bold ${unavailable ? "text-red-400" : "text-emerald-400"}`}
          >
            {unavailable ? "Produk tidak tersedia" : `Stok tersedia: ${product.stock}`}
          </p>
        </Link>
      </div>

      {/* Quantity stepper — hanya muncul untuk produk no-variant yang
          available. Multi-variant tidak punya qty di sini karena harus
          ke PDP untuk pilih variant + qty bersamaan. */}
      {!unavailable && !product.hasVariants && (
        <div className="mt-3 flex items-center gap-3">
          <span className="text-[11px] font-bold uppercase tracking-wide text-white/60">
            Jumlah
          </span>
          <div className="inline-flex items-center gap-1 rounded-full border border-white/10 bg-white/[0.04] p-1">
            <button
              type="button"
              onClick={decQty}
              disabled={quantity <= 1}
              aria-label="Kurangi jumlah"
              className="grid h-7 w-7 place-items-center rounded-full text-white/85 transition active:scale-90 disabled:text-white/25"
            >
              <span className="text-base font-black leading-none">−</span>
            </button>
            <span className="min-w-[28px] text-center text-sm font-black tabular-nums text-white">
              {quantity}
            </span>
            <button
              type="button"
              onClick={incQty}
              disabled={quantity >= maxQty}
              aria-label="Tambah jumlah"
              className="grid h-7 w-7 place-items-center rounded-full text-white/85 transition active:scale-90 disabled:text-white/25"
            >
              <span className="text-base font-black leading-none">+</span>
            </button>
          </div>
          <span className="ml-auto text-[11px] font-semibold text-white/55">
            Total {formatRupiah(pricing.displayPrice * quantity)}
          </span>
        </div>
      )}

      <div className="mt-3 flex items-center gap-3">
        {product.hasVariants ? (
          // Multi-variant: hanya 1 button "Pilih Varian" yg navigasi ke
          // PDP. Tidak boleh quick-add tanpa varian — checkout akan reject.
          <button
            type="button"
            onClick={() => onBuy(1)}
            disabled={unavailable}
            className="relative h-11 min-w-0 flex-1 overflow-hidden rounded-full border border-sky-200/55 bg-[linear-gradient(180deg,rgba(95,191,255,0.96)_0%,rgba(30,135,255,0.94)_44%,rgba(18,97,218,0.96)_100%)] px-5 text-sm font-black text-white shadow-[0_0_26px_rgba(57,154,255,0.46),0_10px_28px_rgba(0,83,189,0.34),inset_0_1px_0_rgba(255,255,255,0.68),inset_0_-2px_8px_rgba(0,52,132,0.34)] transition active:scale-[0.98] disabled:cursor-not-allowed disabled:border-white/8 disabled:bg-none disabled:bg-zinc-700 disabled:text-zinc-400 disabled:shadow-none disabled:active:scale-100"
          >
            <span className="pointer-events-none absolute inset-x-4 top-1 h-3 rounded-full bg-white/38 blur-[5px]" />
            <span className="relative">Pilih Varian</span>
          </button>
        ) : (
          <>
            <button
              type="button"
              aria-label={`Tambahkan ${quantity}× ${product.name} ke keranjang`}
              onClick={() => onAdd(quantity)}
              disabled={unavailable}
              className="grid h-11 w-11 shrink-0 place-items-center rounded-[18px] border border-natalo-400/35 bg-slate-950/35 text-white/90 shadow-[0_0_20px_rgba(48,141,255,0.18),inset_0_1px_0_rgba(255,255,255,0.12)] backdrop-blur-md transition active:scale-95 disabled:cursor-not-allowed disabled:border-white/5 disabled:bg-white/[0.03] disabled:text-zinc-600 disabled:shadow-none disabled:active:scale-100"
            >
              <FiShoppingCart className="h-5 w-5" aria-hidden />
            </button>
            <button
              type="button"
              onClick={() => onBuy(quantity)}
              disabled={unavailable}
              className="relative h-11 min-w-0 flex-1 overflow-hidden rounded-full border border-sky-200/55 bg-[linear-gradient(180deg,rgba(95,191,255,0.96)_0%,rgba(30,135,255,0.94)_44%,rgba(18,97,218,0.96)_100%)] px-5 text-sm font-black text-white shadow-[0_0_26px_rgba(57,154,255,0.46),0_10px_28px_rgba(0,83,189,0.34),inset_0_1px_0_rgba(255,255,255,0.68),inset_0_-2px_8px_rgba(0,52,132,0.34)] transition active:scale-[0.98] disabled:cursor-not-allowed disabled:border-white/8 disabled:bg-none disabled:bg-zinc-700 disabled:text-zinc-400 disabled:shadow-none disabled:active:scale-100"
            >
              <span className="pointer-events-none absolute inset-x-4 top-1 h-3 rounded-full bg-white/38 blur-[5px]" />
              <span className="pointer-events-none absolute inset-x-2 bottom-1 h-1 rounded-full bg-sky-200/35 blur-sm" />
              <span className="relative">Beli Sekarang</span>
            </button>
          </>
        )}
      </div>
    </div>
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
