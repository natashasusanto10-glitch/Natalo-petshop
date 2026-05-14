"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { FiStar } from "react-icons/fi";
import { formatRupiah } from "@/lib/format";
import { addItemToCart } from "@/lib/cart-actions";
import { getWishlistItems, WishlistButton } from "@/components/WishlistButton";
import { AddToCartBottomSheet } from "@/components/AddToCartBottomSheet";
import { StickyBackTitle } from "@/components/StickyBackTitle";
import { EmptyWishlistLottie } from "@/components/wishlist/EmptyWishlistLottie";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";

const RECENT_STORAGE_KEY = "nat-recent-product-views";

type WishlistItem = {
  id: string;
  name: string;
  slug: string;
  price: number;
  memberPrice?: number | null;
  imageUrl: string | null;
  weightGram?: number;
  stock?: number | null;
  hasVariants?: boolean;
};

type RecommendationProduct = {
  id: string;
  slug: string;
  name: string;
  price: number;
  image: string | null;
  rating: number;
  sold_count: number;
};

type RecommendationsResponse = {
  data?: RecommendationProduct[];
  has_more?: boolean;
};

function currentPrice(item: WishlistItem) {
  return item.memberPrice ?? item.price;
}

function readRecentProductIds() {
  try {
    const parsed = JSON.parse(localStorage.getItem(RECENT_STORAGE_KEY) ?? "[]");
    return Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === "string") : [];
  } catch {
    return [];
  }
}

function isOutOfStock(item: WishlistItem) {
  return item.stock !== undefined && item.stock !== null && item.stock <= 0;
}

function cartPayload(item: WishlistItem) {
  const price = currentPrice(item);
  return {
    productId: item.id,
    variantId: null,
    variantLabel: null,
    name: item.name,
    price,
    quantity: 1,
    subtotal: price,
    weightGram: item.weightGram ?? 500,
    stock: item.stock ?? null,
    imageUrl: item.imageUrl,
  };
}

function cartSheetItem(item: WishlistItem) {
  const price = currentPrice(item);
  return {
    productId: item.id,
    variantId: null,
    variantLabel: null,
    name: item.name,
    price,
    weightGram: item.weightGram ?? 500,
    stock: item.stock ?? null,
    imageUrl: item.imageUrl,
  };
}

function RecommendationSkeleton() {
  return (
    <div className="animate-pulse overflow-hidden rounded-xl border border-gray-100 bg-white shadow-sm">
      <div className="aspect-square bg-gray-100" />
      <div className="space-y-2 p-3">
        <div className="h-3 rounded-full bg-gray-100" />
        <div className="h-3 w-2/3 rounded-full bg-gray-100" />
        <div className="mt-3 h-4 w-20 rounded-full bg-gray-100" />
      </div>
    </div>
  );
}

function RecommendationCard({ product }: { product: RecommendationProduct }) {
  return (
    <article className="overflow-hidden rounded-xl border border-gray-100 bg-white shadow-sm">
      <Link href={`/products/${product.slug}`} className="block">
        <div className="relative aspect-square overflow-hidden bg-gray-100">
          {product.image ? (
            <Image
              src={product.image}
              alt={product.name}
              fill
              sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 220px"
              placeholder="blur"
              blurDataURL={IMAGE_BLUR_GRAY}
              className="object-cover transition hover:scale-105"
            />
          ) : (
            <div className="flex h-full items-center justify-center text-3xl font-black text-gray-200">
              NP
            </div>
          )}
        </div>
        <div className="p-2.5">
          <h3 className="line-clamp-2 min-h-[2.35rem] text-[13px] font-bold leading-snug text-gray-900">
            {product.name}
          </h3>
          <p className="mt-1.5 truncate text-sm font-black leading-tight text-natalo-600">
            {formatRupiah(product.price)}
          </p>
          {product.rating > 0 || product.sold_count > 0 ? (
            <p className="mt-1 inline-flex items-center gap-1 text-[11px] font-bold text-gray-500">
              <FiStar className="h-3 w-3 fill-amber-400 text-amber-400" aria-hidden="true" />
              {product.rating > 0 ? product.rating.toFixed(1) : "Baru"}
              {product.sold_count > 0 ? ` · ${product.sold_count} terjual` : ""}
            </p>
          ) : null}
        </div>
      </Link>
    </article>
  );
}

function EmptyWishlistRecommendations() {
  const [recommendations, setRecommendations] = useState<RecommendationProduct[]>([]);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(false);
  const [sentinel, setSentinel] = useState<HTMLDivElement | null>(null);

  async function loadMore() {
    if (loading || !hasMore) return;
    setLoading(true);
    setError(false);

    const viewed = readRecentProductIds();
    const exclude = recommendations.map((product) => product.id);
    const params = new URLSearchParams({
      limit: "10",
      viewed: viewed.join(","),
      exclude: exclude.join(","),
    });

    try {
      const response = await fetch(`/api/cart/recommendations?${params.toString()}`, {
        cache: "no-store",
      });
      if (!response.ok) throw new Error("Failed to load recommendations");
      const data = (await response.json()) as RecommendationsResponse;
      const nextProducts = Array.isArray(data.data) ? data.data : [];
      setRecommendations((current) => {
        const seen = new Set(current.map((product) => product.id));
        return [...current, ...nextProducts.filter((product) => !seen.has(product.id))];
      });
      setHasMore(Boolean(data.has_more));
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadMore();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!sentinel || !hasMore || error) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) void loadMore();
      },
      { rootMargin: "520px 0px" },
    );
    observer.observe(sentinel);
    return () => observer.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sentinel, hasMore, error, recommendations.length, loading]);

  return (
    <section className="mt-6">
      <h2 className="px-1 text-lg font-black text-slate-950">Rekomendasi untuk kamu</h2>

      {recommendations.length === 0 && loading ? (
        <div className="mt-3 grid grid-cols-2 gap-2.5 sm:gap-4 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, index) => (
            <RecommendationSkeleton key={index} />
          ))}
        </div>
      ) : (
        <div className="mt-3 grid grid-cols-2 gap-2.5 sm:gap-4 lg:grid-cols-3">
          {recommendations.map((product) => (
            <RecommendationCard key={product.id} product={product} />
          ))}
        </div>
      )}

      {loading && recommendations.length > 0 && (
        <div className="mt-3 grid grid-cols-2 gap-2.5 sm:gap-4 lg:grid-cols-3">
          {Array.from({ length: 3 }).map((_, index) => (
            <RecommendationSkeleton key={index} />
          ))}
        </div>
      )}

      {error && (
        <p className="mt-4 rounded-2xl border border-red-100 bg-red-50 p-4 text-center text-sm font-bold text-red-600">
          Rekomendasi belum bisa dimuat.
        </p>
      )}

      {!hasMore && recommendations.length > 0 && (
        <p className="mt-4 text-center text-xs font-semibold text-gray-400">
          Kamu sudah melihat semuanya
        </p>
      )}

      <div ref={setSentinel} className="h-8" />
    </section>
  );
}

export default function WishlistPage() {
  const router = useRouter();
  const [items, setItems] = useState<WishlistItem[]>([]);
  const [addedIds, setAddedIds] = useState<Set<string>>(new Set());
  const [variantItem, setVariantItem] = useState<WishlistItem | null>(null);
  const [sheetItem, setSheetItem] = useState<ReturnType<typeof cartSheetItem> | null>(null);

  useEffect(() => {
    function sync() {
      setItems(getWishlistItems());
    }
    sync();
    window.addEventListener("wishlist-updated", sync);
    return () => window.removeEventListener("wishlist-updated", sync);
  }, []);

  function handleAddToCart(item: WishlistItem) {
    if (isOutOfStock(item)) return;
    if (item.hasVariants) {
      setVariantItem(item);
      return;
    }

    setSheetItem(cartSheetItem(item));
  }

  function handleAddedToCart(productId: string) {
    setAddedIds((prev) => new Set(prev).add(productId));
    setTimeout(() => {
      setAddedIds((prev) => {
        const next = new Set(prev);
        next.delete(productId);
        return next;
      });
    }, 1800);
  }

  function handleBuyNow(item: WishlistItem) {
    if (isOutOfStock(item)) return;
    if (item.hasVariants) {
      setVariantItem(item);
      return;
    }

    const result = addItemToCart(cartPayload(item), { showToast: false });
    if (result.ok) router.push("/checkout");
  }

  return (
    <div className="min-h-screen bg-slate-50">
      <StickyBackTitle
        label="Wishlist"
        subtitle={`${items.length} produk disimpan`}
        fallbackHref="/member"
        stickToTop
        rightAction={
          items.length > 0 ? (
            <Link href="/products" className="text-xs font-extrabold text-natalo-600">
              Belanja Lagi
            </Link>
          ) : null
        }
      />

      <div className="mx-auto max-w-4xl px-3 py-4 pb-36 md:px-4 md:py-8 md:pb-10">

      {items.length === 0 ? (
        <>
          <div className="mt-8 rounded-2xl border border-blue-100 bg-white p-6 text-center shadow-[0_12px_34px_rgba(15,23,42,0.06)] md:p-10">
            <EmptyWishlistLottie />
            <h2 className="text-xl font-black leading-tight text-[#07112F]">
              Wishlist kamu masih kosong
            </h2>
            <p className="mx-auto mt-2 max-w-md text-sm font-semibold leading-relaxed text-gray-500">
              Simpan makanan, vitamin, pasir, atau perlengkapan favorit agar mudah dibeli lagi nanti.
            </p>
            <p className="mt-3 text-xs font-bold text-[#6B7280]">
              Tekan ikon hati pada produk yang kamu suka.
            </p>
            <Link
              href="/products"
              className="mt-5 inline-flex rounded-xl bg-natalo-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-natalo-700"
            >
              Jelajahi Produk
            </Link>
          </div>
          <EmptyWishlistRecommendations />
        </>
      ) : (
        <div className="mt-4 grid grid-cols-2 gap-2.5 sm:gap-4 lg:grid-cols-3">
          {items.map((item) => {
            const outOfStock = isOutOfStock(item);
            const added = addedIds.has(item.id);
            return (
              <article
                key={item.id}
                className="group relative flex min-w-0 flex-col overflow-hidden rounded-xl border border-gray-100 bg-white shadow-sm"
              >
                <Link href={`/products/${item.slug}`} className="block">
                  <div className="relative aspect-square overflow-hidden bg-gray-100">
                    {item.imageUrl ? (
                      <Image
                        src={item.imageUrl}
                        alt={item.name}
                        fill
                        sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 220px"
                        placeholder="blur"
                        blurDataURL={IMAGE_BLUR_GRAY}
                        className="object-cover transition group-hover:scale-105"
                      />
                    ) : (
                      <div className="flex h-full items-center justify-center text-3xl font-black text-gray-200">
                        NP
                      </div>
                    )}
                  </div>
                </Link>

                <div className="absolute right-2 top-2">
                  <WishlistButton product={item} size="sm" />
                </div>

                <div className="flex flex-1 flex-col p-2.5">
                  <Link href={`/products/${item.slug}`} className="min-w-0">
                    <h2 className="line-clamp-2 min-h-[2.35rem] text-[13px] font-bold leading-snug text-gray-900">
                      {item.name}
                    </h2>
                  </Link>

                  <div className="mt-1.5">
                    <p className="truncate text-sm font-black leading-tight text-natalo-600">
                      {formatRupiah(currentPrice(item))}
                    </p>
                    {item.memberPrice !== null && item.memberPrice !== undefined && item.memberPrice < item.price && (
                      <p className="mt-0.5 truncate text-[11px] text-gray-400 line-through">
                        {formatRupiah(item.price)}
                      </p>
                    )}
                  </div>

                  <div className="mt-3 flex w-full gap-2">
                    <button
                      type="button"
                      onClick={() => handleAddToCart(item)}
                      disabled={outOfStock}
                      aria-label={added ? "Sudah masuk keranjang" : "Tambah ke keranjang"}
                      className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-blue-600 bg-white text-blue-600 transition active:bg-blue-50 disabled:cursor-not-allowed disabled:border-gray-200 disabled:text-gray-300"
                    >
                      <svg
                        aria-hidden="true"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        className="h-5 w-5"
                      >
                        <circle cx="8" cy="21" r="1" />
                        <circle cx="19" cy="21" r="1" />
                        <path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12" />
                      </svg>
                    </button>
                    <button
                      type="button"
                      onClick={() => handleBuyNow(item)}
                      disabled={outOfStock}
                      className="h-11 flex-1 whitespace-nowrap rounded-xl bg-blue-700 text-sm font-semibold text-white transition active:bg-blue-800 disabled:cursor-not-allowed disabled:bg-gray-300"
                    >
                      {outOfStock ? "Stok Habis" : "Beli Sekarang"}
                    </button>
                  </div>
                </div>
              </article>
            );
          })}
        </div>
      )}

      {variantItem && (
        <div className="fixed inset-0 z-[70] flex items-end bg-black/35 px-3 pb-[calc(86px+env(safe-area-inset-bottom))] md:hidden">
          <div className="w-full rounded-2xl bg-white p-4 shadow-xl">
            <div className="flex gap-3">
              <div className="relative h-16 w-16 shrink-0 overflow-hidden rounded-xl bg-gray-100">
                {variantItem.imageUrl ? (
                  <Image
                    src={variantItem.imageUrl}
                    alt={variantItem.name}
                    fill
                    placeholder="blur"
                    blurDataURL={IMAGE_BLUR_GRAY}
                    className="object-cover"
                  />
                ) : (
                  <div className="flex h-full items-center justify-center text-sm font-black text-gray-300">
                    NP
                  </div>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <p className="line-clamp-2 text-sm font-extrabold text-gray-900">{variantItem.name}</p>
                <p className="mt-1 text-sm font-black text-natalo-600">
                  {formatRupiah(currentPrice(variantItem))}
                </p>
              </div>
            </div>
            <p className="mt-3 text-sm leading-6 text-gray-600">
              Produk ini punya pilihan varian. Pilih varian terlebih dahulu agar checkout sesuai.
            </p>
            <div className="mt-4 grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setVariantItem(null)}
                className="h-11 rounded-xl border border-gray-200 text-sm font-extrabold text-gray-700"
              >
                Nanti
              </button>
              <button
                type="button"
                onClick={() => router.push(`/products/${variantItem.slug}`)}
                className="h-11 rounded-xl bg-natalo-600 text-sm font-extrabold text-white"
              >
                Pilih Varian
              </button>
            </div>
          </div>
        </div>
      )}
      <AddToCartBottomSheet
        open={!!sheetItem}
        item={sheetItem}
        onClose={() => setSheetItem(null)}
        onAdded={() => {
          if (sheetItem) handleAddedToCart(sheetItem.productId);
        }}
      />
      </div>
    </div>
  );
}
