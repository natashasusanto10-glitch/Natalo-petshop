"use client";

import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { FiChevronRight, FiRefreshCw, FiShoppingCart, FiStar } from "react-icons/fi";
import { BottomSheet } from "@/components/BottomSheet";
import { natToast } from "@/components/Toast";
import { addItemToCart } from "@/lib/cart-actions";
import type { CartItem } from "@/lib/cart";
import { formatRupiah } from "@/lib/format";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import { hapticError, hapticSuccess, hapticTap } from "@/lib/native/haptics";

const RECENT_STORAGE_KEY = "nat-recent-product-views";

type VariantAttribute = {
  id: string;
  name: string;
  position: number;
  options: { id: string; value: string; position: number }[];
};

type ProductVariant = {
  id: string;
  price: number;
  stock: number;
  weightGram: number;
  imageUrl: string | null;
  isActive: boolean;
  deletedAt: string | null;
  options: { optionId: string }[];
};

export type CartRecommendationProduct = {
  id: string;
  slug: string;
  name: string;
  price: number;
  normal_price: number | null;
  discount_price: number | null;
  discount_percent: number | null;
  image: string | null;
  stock: number;
  weightGram: number;
  rating: number;
  sold_count: number;
  hasVariants: boolean;
  category: string | null;
  brand: string | null;
  variantAttrs: VariantAttribute[];
  variants: ProductVariant[];
};

type RecommendationsResponse = {
  data?: CartRecommendationProduct[];
  next_cursor?: string | null;
  has_more?: boolean;
};

type Props = {
  cartItems: CartItem[];
};

function cartProductIds(items: CartItem[]) {
  return Array.from(new Set(items.map((item) => item.productId).filter(Boolean)));
}

function readRecentProductIds() {
  try {
    const parsed = JSON.parse(localStorage.getItem(RECENT_STORAGE_KEY) ?? "[]");
    return Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === "string") : [];
  } catch {
    return [];
  }
}

function uniqueIds(ids: string[]) {
  return Array.from(new Set(ids.filter(Boolean)));
}

function productCartItem(product: CartRecommendationProduct): CartItem {
  return {
    productId: product.id,
    slug: product.slug,
    variantId: null,
    variantLabel: null,
    name: product.name,
    price: product.price,
    quantity: 1,
    subtotal: product.price,
    weightGram: product.weightGram,
    stock: product.stock,
    imageUrl: product.image,
  };
}

function RecommendationSkeleton({ compact = false }: { compact?: boolean }) {
  return (
    <div
      className={`animate-pulse rounded-2xl border border-gray-100 bg-white p-3 shadow-sm ${
        compact ? "w-36 shrink-0" : ""
      }`}
    >
      <div className="aspect-square rounded-xl bg-gray-100" />
      <div className="mt-3 h-3 rounded-full bg-gray-100" />
      <div className="mt-2 h-3 w-2/3 rounded-full bg-gray-100" />
      <div className="mt-3 h-4 w-20 rounded-full bg-gray-100" />
    </div>
  );
}

function SectionHeader({ title }: { title: string }) {
  return (
    <div className="mb-3 flex items-center justify-between gap-3">
      <h2 className="text-base font-black text-gray-950">{title}</h2>
      <Link
        href="/products"
        className="inline-flex h-9 shrink-0 items-center gap-1 rounded-full px-2 text-xs font-black text-blue-600 active:bg-blue-50"
      >
        Lihat semua
        <FiChevronRight className="h-4 w-4" aria-hidden />
      </Link>
    </div>
  );
}

function ProductCard({
  product,
  compact = false,
  onAdd,
}: {
  product: CartRecommendationProduct;
  compact?: boolean;
  onAdd: (product: CartRecommendationProduct) => void;
}) {
  const hasDiscount = Boolean(product.normal_price && product.normal_price > product.price);

  return (
    <article
      className={`relative rounded-2xl border border-gray-100 bg-white p-3 shadow-[0_8px_24px_-18px_rgba(15,23,42,0.35)] ${
        compact ? "w-40 shrink-0" : ""
      }`}
    >
      <Link href={`/products/${product.slug}`} className="block" aria-label={`Lihat ${product.name}`}>
        <div className="relative aspect-square overflow-hidden rounded-xl bg-gray-50">
          {product.image ? (
            <Image
              src={product.image}
              alt={product.name}
              fill
              sizes={compact ? "160px" : "(max-width: 768px) 50vw, 220px"}
              placeholder="blur"
              blurDataURL={IMAGE_BLUR_GRAY}
              className="object-contain p-2"
            />
          ) : (
            <div className="flex h-full items-center justify-center text-xs font-bold text-gray-300">
              No image
            </div>
          )}
          {product.discount_percent ? (
            <span className="absolute left-2 top-2 rounded-full bg-red-500 px-2 py-1 text-[10px] font-black text-white">
              -{product.discount_percent}%
            </span>
          ) : null}
        </div>
        <h3 className="mt-3 line-clamp-2 min-h-9 text-[12.5px] font-bold leading-snug text-gray-900">
          {product.name}
        </h3>
        <div className="mt-2 min-h-10">
          <p className="text-sm font-black text-blue-600">{formatRupiah(product.price)}</p>
          {hasDiscount && product.normal_price ? (
            <p className="text-[11px] font-semibold text-gray-400 line-through">
              {formatRupiah(product.normal_price)}
            </p>
          ) : null}
        </div>
        {product.rating > 0 || product.sold_count > 0 ? (
          <p className="mt-1 inline-flex items-center gap-1 text-[11px] font-bold text-gray-500">
            <FiStar className="h-3 w-3 fill-amber-400 text-amber-400" aria-hidden />
            {product.rating > 0 ? product.rating.toFixed(1) : "Baru"}
            {product.sold_count > 0 ? ` · ${product.sold_count} ulasan` : ""}
          </p>
        ) : null}
      </Link>
      <button
        type="button"
        onClick={() => onAdd(product)}
        aria-label={`Tambah ${product.name} ke keranjang`}
        className="absolute bottom-3 right-3 grid h-10 w-10 place-items-center rounded-full bg-blue-600 text-white shadow-[0_8px_18px_-8px_rgba(37,99,235,0.55)] transition active:scale-95 disabled:bg-gray-300"
        disabled={product.stock <= 0}
      >
        <FiShoppingCart className="h-4 w-4" aria-hidden />
      </button>
    </article>
  );
}

function VariantChoiceSheet({
  product,
  onClose,
  onAdded,
}: {
  product: CartRecommendationProduct | null;
  onClose: () => void;
  onAdded: () => void;
}) {
  const [selected, setSelected] = useState<Record<string, string>>({});
  const activeProductId = product?.id ?? null;

  useEffect(() => {
    setSelected({});
  }, [activeProductId]);

  const sortedAttrs = useMemo(
    () => [...(product?.variantAttrs ?? [])].sort((a, b) => a.position - b.position),
    [product?.variantAttrs],
  );
  const allSelected = product ? sortedAttrs.every((attr) => selected[attr.id]) : false;
  const currentVariant = useMemo(() => {
    if (!product || !allSelected) return null;
    return (
      product.variants.find(
        (variant) =>
          variant.isActive &&
          !variant.deletedAt &&
          variant.stock > 0 &&
          sortedAttrs.every((attr) =>
            variant.options.some((option) => option.optionId === selected[attr.id]),
          ),
      ) ?? null
    );
  }, [allSelected, product, selected, sortedAttrs]);
  const selectedLabel = useMemo(
    () =>
      sortedAttrs
        .map((attr) => attr.options.find((option) => option.id === selected[attr.id])?.value ?? "")
        .filter(Boolean)
        .join(" / "),
    [selected, sortedAttrs],
  );
  const price = currentVariant?.price ?? product?.price ?? 0;

  function isOptionDisabled(attrIndex: number, optionId: string) {
    if (!product) return true;
    return !product.variants.some((variant) => {
      if (!variant.isActive || variant.deletedAt || variant.stock <= 0) return false;
      if (!variant.options.some((option) => option.optionId === optionId)) return false;
      for (let index = 0; index < attrIndex; index += 1) {
        const chosen = selected[sortedAttrs[index].id];
        if (chosen && !variant.options.some((option) => option.optionId === chosen)) return false;
      }
      return true;
    });
  }

  function addVariantToCart() {
    if (!product || !currentVariant) return;
    const result = addItemToCart(
      {
        productId: product.id,
        slug: product.slug,
        variantId: currentVariant.id,
        variantLabel: selectedLabel,
        name: product.name,
        price: currentVariant.price,
        quantity: 1,
        subtotal: currentVariant.price,
        weightGram: currentVariant.weightGram,
        stock: currentVariant.stock,
        imageUrl: currentVariant.imageUrl ?? product.image,
      },
      { successMessage: "Produk berhasil ditambahkan ke keranjang" },
    );
    if (!result.ok) {
      hapticError();
      return;
    }
    hapticSuccess();
    onAdded();
    onClose();
  }

  return (
    <BottomSheet
      open={Boolean(product)}
      onClose={onClose}
      title="Pilih Varian"
      footer={
        <button
          type="button"
          onClick={addVariantToCart}
          disabled={!currentVariant}
          className="h-12 w-full rounded-full bg-blue-600 text-sm font-black text-white transition active:scale-95 disabled:cursor-not-allowed disabled:bg-gray-300"
        >
          Tambah ke Keranjang
        </button>
      }
    >
      {product && (
        <div className="space-y-5">
          <div className="flex gap-3 rounded-2xl bg-gray-50 p-3">
            <div className="relative h-20 w-20 shrink-0 overflow-hidden rounded-xl bg-white">
              {product.image ? (
                <Image
                  src={currentVariant?.imageUrl ?? product.image}
                  alt={product.name}
                  fill
                  sizes="80px"
                  className="object-contain p-2"
                />
              ) : null}
            </div>
            <div className="min-w-0 flex-1">
              <p className="line-clamp-2 text-sm font-black text-gray-950">{product.name}</p>
              <p className="mt-2 text-lg font-black text-blue-600">{formatRupiah(price)}</p>
              <p className="text-xs font-bold text-gray-500">
                {currentVariant ? `Stok ${currentVariant.stock}` : "Pilih varian tersedia"}
              </p>
            </div>
          </div>

          {sortedAttrs.map((attr, attrIndex) => (
            <div key={attr.id}>
              <p className="text-sm font-black text-gray-900">{attr.name}</p>
              <div className="mt-2 flex flex-wrap gap-2">
                {[...attr.options]
                  .sort((a, b) => a.position - b.position)
                  .map((option) => {
                    const disabled = isOptionDisabled(attrIndex, option.id);
                    const active = selected[attr.id] === option.id;
                    return (
                      <button
                        key={option.id}
                        type="button"
                        disabled={disabled}
                        onClick={() => {
                          hapticTap();
                          setSelected((current) => ({ ...current, [attr.id]: option.id }));
                        }}
                        className={`min-h-11 rounded-2xl border px-4 text-sm font-bold transition ${
                          active
                            ? "border-blue-600 bg-blue-50 text-blue-700"
                            : disabled
                              ? "cursor-not-allowed border-gray-100 bg-gray-50 text-gray-300 line-through"
                              : "border-gray-200 bg-white text-gray-700 active:border-blue-300"
                        }`}
                      >
                        {option.value}
                      </button>
                    );
                  })}
              </div>
            </div>
          ))}
        </div>
      )}
    </BottomSheet>
  );
}

export function CartRecommendationSections({ cartItems }: Props) {
  const [recentlyViewed, setRecentlyViewed] = useState<CartRecommendationProduct[]>([]);
  const [viewedSourceIds, setViewedSourceIds] = useState<string[]>([]);
  const [recentLoading, setRecentLoading] = useState(false);
  const [recommendations, setRecommendations] = useState<CartRecommendationProduct[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [recommendationError, setRecommendationError] = useState(false);
  const [variantProduct, setVariantProduct] = useState<CartRecommendationProduct | null>(null);
  const sentinelRef = useRef<HTMLDivElement | null>(null);
  const recommendationsRef = useRef<CartRecommendationProduct[]>([]);
  const cursorRef = useRef<string | null>(null);
  const hasMoreRef = useRef(true);
  const loadingRef = useRef(false);
  const recommendationRequestRef = useRef(0);
  const cartIds = useMemo(() => cartProductIds(cartItems), [cartItems]);
  const cartIdsKey = cartIds.join(",");
  const recentIds = useMemo(() => recentlyViewed.map((product) => product.id), [recentlyViewed]);
  const behaviorIdsKey = useMemo(
    () => uniqueIds([...viewedSourceIds, ...recentIds]).join(","),
    [recentIds, viewedSourceIds],
  );

  useEffect(() => {
    recommendationsRef.current = recommendations;
  }, [recommendations]);

  useEffect(() => {
    cursorRef.current = cursor;
  }, [cursor]);

  useEffect(() => {
    hasMoreRef.current = hasMore;
  }, [hasMore]);

  const addProduct = useCallback((product: CartRecommendationProduct) => {
    if (product.stock <= 0) {
      hapticError();
      natToast("Stok produk habis", { kind: "err" });
      return;
    }
    if (product.hasVariants) {
      hapticTap();
      setVariantProduct(product);
      return;
    }
    const result = addItemToCart(productCartItem(product), {
      successMessage: "Produk berhasil ditambahkan ke keranjang",
    });
    if (result.ok) hapticSuccess();
    else hapticError();
  }, []);

  useEffect(() => {
    let active = true;
    const currentCartIds = cartIdsKey ? cartIdsKey.split(",") : [];
    const localRecentIds = readRecentProductIds().filter((id) => !currentCartIds.includes(id));
    setViewedSourceIds(localRecentIds);
    setRecentLoading(true);
    const params = new URLSearchParams({
      limit: "10",
      ids: localRecentIds.join(","),
      exclude: currentCartIds.join(","),
    });
    fetch(`/api/cart/recently-viewed?${params.toString()}`, { cache: "no-store" })
      .then((response) => (response.ok ? response.json() : { data: [] }))
      .then((data: RecommendationsResponse) => {
        if (!active) return;
        const nextRecentlyViewed = Array.isArray(data.data) ? data.data : [];
        setRecentlyViewed(nextRecentlyViewed);
        setViewedSourceIds(uniqueIds([...localRecentIds, ...nextRecentlyViewed.map((product) => product.id)]));
      })
      .catch(() => {
        if (active) setRecentlyViewed([]);
      })
      .finally(() => {
        if (active) setRecentLoading(false);
      });
    return () => {
      active = false;
    };
  }, [cartIdsKey]);

  const loadRecommendations = useCallback(
    async (reset = false) => {
      if (loadingRef.current && !reset) return;
      if (!reset && !hasMoreRef.current) return;
      const requestId = recommendationRequestRef.current + 1;
      recommendationRequestRef.current = requestId;
      loadingRef.current = true;
      setLoadingMore(true);
      setRecommendationError(false);
      const currentCartIds = cartIdsKey ? cartIdsKey.split(",") : [];
      const currentBehaviorIds = behaviorIdsKey ? behaviorIdsKey.split(",") : [];
      const alreadyShown = reset ? [] : recommendationsRef.current.map((product) => product.id);
      const exclude = Array.from(new Set([...currentCartIds, ...currentBehaviorIds, ...alreadyShown]));
      const params = new URLSearchParams({
        limit: "10",
        cart: currentCartIds.join(","),
        viewed: currentBehaviorIds.join(","),
        exclude: exclude.join(","),
      });
      if (!reset && cursorRef.current) params.set("cursor", cursorRef.current);

      try {
        const response = await fetch(`/api/cart/recommendations?${params.toString()}`, {
          cache: "no-store",
        });
        if (!response.ok) throw new Error("Failed to load recommendations");
        const data = (await response.json()) as RecommendationsResponse;
        if (requestId !== recommendationRequestRef.current) return;
        const nextProducts = Array.isArray(data.data) ? data.data : [];
        setRecommendations((current) => {
          if (reset) return nextProducts;
          const seen = new Set(current.map((product) => product.id));
          return [...current, ...nextProducts.filter((product) => !seen.has(product.id))];
        });
        setCursor(data.next_cursor ?? null);
        setHasMore(Boolean(data.has_more));
      } catch {
        if (requestId !== recommendationRequestRef.current) return;
        setRecommendationError(true);
      } finally {
        if (requestId === recommendationRequestRef.current) {
          loadingRef.current = false;
          setLoadingMore(false);
        }
      }
    },
    [behaviorIdsKey, cartIdsKey],
  );

  useEffect(() => {
    recommendationsRef.current = [];
    cursorRef.current = null;
    hasMoreRef.current = true;
    setRecommendations([]);
    setCursor(null);
    setHasMore(true);
    void loadRecommendations(true);
  }, [cartIdsKey, behaviorIdsKey, loadRecommendations]);

  useEffect(() => {
    const node = sentinelRef.current;
    if (!node || !hasMore || recommendationError) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) void loadRecommendations(false);
      },
      { rootMargin: "520px 0px" },
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, [hasMore, loadRecommendations, recommendationError]);

  return (
    <div className="mt-5 space-y-6 pb-[120px] md:pb-6">
      {(recentLoading || recentlyViewed.length > 0) && (
        <section>
          <SectionHeader title="Kamu sempat lihat-lihat ini" />
          <div className="-mx-4 flex gap-3 overflow-x-auto px-4 pb-2 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            {recentLoading
              ? Array.from({ length: 4 }).map((_, index) => (
                  <RecommendationSkeleton compact key={index} />
                ))
              : recentlyViewed.map((product) => (
                  <ProductCard compact key={product.id} product={product} onAdd={addProduct} />
                ))}
          </div>
        </section>
      )}

      <section>
        <SectionHeader title="Rekomendasi untukmu" />
        {recommendations.length === 0 && loadingMore ? (
          <div className="grid grid-cols-2 gap-3">
            {Array.from({ length: 4 }).map((_, index) => (
              <RecommendationSkeleton key={index} />
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-3">
            {recommendations.map((product) => (
              <ProductCard key={product.id} product={product} onAdd={addProduct} />
            ))}
          </div>
        )}

        {loadingMore && recommendations.length > 0 && (
          <div className="mt-3 grid grid-cols-2 gap-3">
            {Array.from({ length: 4 }).map((_, index) => (
              <RecommendationSkeleton key={index} />
            ))}
          </div>
        )}

        {recommendationError && (
          <div className="mt-4 rounded-2xl border border-red-100 bg-red-50 p-4 text-center">
            <p className="text-sm font-bold text-red-600">Rekomendasi belum bisa dimuat.</p>
            <button
              type="button"
              onClick={() => void loadRecommendations(false)}
              className="mt-3 inline-flex h-10 items-center gap-2 rounded-full bg-white px-4 text-xs font-black text-red-600 ring-1 ring-red-100"
            >
              <FiRefreshCw className="h-4 w-4" aria-hidden />
              Muat ulang
            </button>
          </div>
        )}

        {!hasMore && recommendations.length > 0 && (
          <p className="mt-4 text-center text-xs font-semibold text-gray-400">
            Semua rekomendasi sudah ditampilkan
          </p>
        )}
        <div ref={sentinelRef} className="h-8" />
      </section>

      <VariantChoiceSheet
        product={variantProduct}
        onClose={() => setVariantProduct(null)}
        onAdded={() => {
          setRecommendations((current) =>
            current.filter((product) => product.id !== variantProduct?.id),
          );
          setRecentlyViewed((current) =>
            current.filter((product) => product.id !== variantProduct?.id),
          );
        }}
      />
    </div>
  );
}
