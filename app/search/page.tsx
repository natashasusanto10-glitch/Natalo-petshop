"use client";

import Image from "next/image";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import Link from "next/link";
import { Suspense, useEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { BottomSheet } from "@/components/BottomSheet";
import { PageStatusBar } from "@/components/PageStatusBar";
import { QuickAddToCart } from "@/components/QuickAddToCart";
import {
  SearchFilters,
  type ActiveFilters,
  type Facets,
} from "@/components/SearchFilters";
import { formatRupiah } from "@/lib/format";
import { buildKeywordOnlySearchHref, buildKeywordOnlySearchParams } from "@/lib/search-url";

type SearchItem = {
  id: string;
  slug: string;
  name: string;
  image_url: string | null;
  price_min: number;
  price_max: number;
  discount_price: number | null;
  stock: number;
  total_stock: number;
  weight_grams: number;
  brand_name: string | null;
  brand_slug: string | null;
  category_name: string | null;
  avg_rating: number;
  review_count: number;
  is_active: boolean;
  has_variants: boolean;
};

type SearchResult = {
  items: SearchItem[];
  total: number;
  page: number;
  per_page: number;
  facets: Facets;
  took_ms?: number;
};

type Suggest = {
  products: Array<{
    id: string;
    slug: string;
    name: string;
    image_url: string | null;
    price_min: number;
    price_max: number;
    brand_name: string | null;
  }>;
  categories: Array<{ slug: string; name: string; count: number }>;
  brands: Array<{ slug: string; name: string; count: number }>;
  total: number;
};

type Sort =
  | "relevance"
  | "price_asc"
  | "price_desc"
  | "newest"
  | "best_seller"
  | "rating_desc";

const EMPTY_SUGGEST: Suggest = {
  products: [],
  categories: [],
  brands: [],
  total: 0,
};

const EMPTY_FACETS: Facets = {
  categories: [],
  brands: [],
  price_range: { min: 0, max: 0 },
  weights: [],
};

const SORT_OPTIONS: { value: Sort; label: string }[] = [
  { value: "relevance", label: "Relevansi" },
  { value: "price_asc", label: "Harga terendah" },
  { value: "price_desc", label: "Harga tertinggi" },
  { value: "newest", label: "Terbaru" },
  { value: "best_seller", label: "Terlaris" },
];

const NON_SELECTABLE_TOUCH_STYLE = {
  userSelect: "none",
  WebkitTouchCallout: "none",
} as CSSProperties;

function isSupportedSort(value: string | null): value is Sort {
  return SORT_OPTIONS.some((option) => option.value === value);
}

function SearchPageContent() {
  const router = useRouter();
  const sp = useSearchParams();
  const q = sp.get("q") ?? "";
  const page = Math.max(1, Number(sp.get("page")) || 1);
  const sortParam = sp.get("sort");
  const sort: Sort = isSupportedSort(sortParam) ? sortParam : "relevance";
  const categorySlugs = sp.getAll("category");
  const brandSlugs = sp.getAll("brand");
  const minPrice = sp.get("min_price") ? Number(sp.get("min_price")) : undefined;
  const maxPrice = sp.get("max_price") ? Number(sp.get("max_price")) : undefined;
  const inStock = sp.get("in_stock") === "true";
  const minRating = sp.get("min_rating") ? Number(sp.get("min_rating")) : undefined;

  const filters: ActiveFilters = useMemo(
    () => ({
      categorySlugs,
      brandSlugs,
      minPrice,
      maxPrice,
      inStock,
      minRating,
    }),
    [
      categorySlugs.join(","),
      brandSlugs.join(","),
      minPrice,
      maxPrice,
      inStock,
      minRating,
    ],
  );

  const [data, setData] = useState<SearchResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [sortOpen, setSortOpen] = useState(false);
  const [filterOpen, setFilterOpen] = useState(false);

  function buildSearchParams(includePage = true) {
    const params = new URLSearchParams();
    if (q) params.set("q", q);
    categorySlugs.forEach((category) => params.append("category", category));
    brandSlugs.forEach((brand) => params.append("brand", brand));
    if (minPrice !== undefined) params.set("min_price", String(minPrice));
    if (maxPrice !== undefined) params.set("max_price", String(maxPrice));
    if (inStock) params.set("in_stock", "true");
    if (minRating !== undefined) params.set("min_rating", String(minRating));
    params.set("sort", sort);
    if (includePage) {
      params.set("page", String(page));
      params.set("per_page", "24");
    }
    return params;
  }

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);

    const searchParams = buildSearchParams(true);

    fetch(`/api/search?${searchParams}`, { signal: controller.signal })
      .then((response) => response.json())
      .then((searchData) => {
        setData({
          ...searchData,
          facets: searchData.facets ?? EMPTY_FACETS,
        });
      })
      .catch((error) => {
        if (error instanceof Error && error.name === "AbortError") return;
        setData({ items: [], total: 0, page: 1, per_page: 24, facets: EMPTY_FACETS });
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    return () => controller.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    q,
    sort,
    page,
    categorySlugs.join(","),
    brandSlugs.join(","),
    minPrice,
    maxPrice,
    inStock,
    minRating,
  ]);

  function applyFilters(next: ActiveFilters) {
    const params = new URLSearchParams();
    if (q) params.set("q", q);
    next.categorySlugs.forEach((category) => params.append("category", category));
    next.brandSlugs.forEach((brand) => params.append("brand", brand));
    if (next.minPrice !== undefined) params.set("min_price", String(next.minPrice));
    if (next.maxPrice !== undefined) params.set("max_price", String(next.maxPrice));
    if (next.inStock) params.set("in_stock", "true");
    if (next.minRating !== undefined) params.set("min_rating", String(next.minRating));
    if (sort !== "relevance") params.set("sort", sort);
    router.push(`/search?${params}`);
  }

  function resetFilters() {
    router.push(buildKeywordOnlySearchHref(q));
  }

  function updateParam(key: string, value: string | null) {
    const next = new URLSearchParams(sp);
    if (value === null || value === "") next.delete(key);
    else next.set(key, value);
    if (key !== "page") next.delete("page");
    router.push(`/search?${next}`);
  }

  function removeFilterChip(type: "category" | "brand", value: string) {
    const next = new URLSearchParams(sp);
    const all = next.getAll(type);
    next.delete(type);
    all.filter((filterValue) => filterValue !== value).forEach((filterValue) => {
      next.append(type, filterValue);
    });
    next.delete("page");
    router.push(`/search?${next}`);
  }

  const totalPages = data ? Math.max(1, Math.ceil(data.total / data.per_page)) : 1;
  const facets = data?.facets ?? null;
  const hasActiveFilters =
    categorySlugs.length > 0 ||
    brandSlugs.length > 0 ||
    minPrice !== undefined ||
    maxPrice !== undefined ||
    inStock ||
    minRating !== undefined;
  const activeFilterCount =
    categorySlugs.length +
    brandSlugs.length +
    (minPrice !== undefined || maxPrice !== undefined ? 1 : 0) +
    (inStock ? 1 : 0) +
    (minRating !== undefined ? 1 : 0);
  const activeSortOption = SORT_OPTIONS.find((option) => option.value === sort) ?? SORT_OPTIONS[0];
  const canResetSearchControls = hasActiveFilters || sort !== "relevance" || page !== 1;

  return (
    <div className="min-h-screen bg-gray-50 pb-[calc(6rem+env(safe-area-inset-bottom))] md:bg-white md:pb-12">
      <PageStatusBar
        iconColor="dark"
        themeColor="#ffffff"
        nativeBackgroundColor="#ffffff"
        overlaysWebView={false}
      />
      <SearchResultHeader query={q} />

      <div className="mx-auto max-w-6xl px-3 py-4 md:px-4 md:py-6">
        <div className="rounded-2xl border border-gray-100 bg-white p-3 shadow-sm md:border-0 md:p-0 md:shadow-none">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <h1 className="truncate text-sm font-black text-gray-950 md:text-base">
                {q ? `Hasil untuk "${q}"` : "Semua produk"}
              </h1>
              <p className="mt-0.5 text-xs font-semibold text-gray-500">
                {loading ? "Mencari produk..." : `${data?.total ?? 0} produk ditemukan`}
              </p>
            </div>
          </div>

          <div className="mt-3 flex items-center gap-2 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            <button
              type="button"
              onClick={() => setSortOpen(true)}
              aria-haspopup="dialog"
              aria-expanded={sortOpen}
              aria-label={`Urutkan produk, saat ini ${activeSortOption.label}`}
              className="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full border border-gray-200 bg-white px-3 text-xs font-extrabold text-gray-800 outline-none active:bg-gray-50 focus:border-natalo-500 focus:ring-2 focus:ring-natalo-100"
              style={NON_SELECTABLE_TOUCH_STYLE}
            >
              Urut: {activeSortOption.label}
              <ChevronDownIcon className="h-4 w-4 text-gray-400" />
            </button>

            <button
              type="button"
              onClick={() => setFilterOpen(true)}
              className="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full border border-gray-200 bg-white px-3 text-xs font-extrabold text-gray-800 active:bg-gray-50 md:hidden"
              style={NON_SELECTABLE_TOUCH_STYLE}
            >
              <FilterIcon className="h-4 w-4 text-natalo-600" />
              Filter
              {hasActiveFilters && (
                <span className="ml-0.5 rounded-full bg-natalo-600 px-1.5 py-0.5 text-[10px] leading-none text-white">
                  {activeFilterCount}
                </span>
              )}
            </button>
          </div>
        </div>

        {canResetSearchControls && (
          <div className="mt-3 flex flex-wrap items-center gap-2">
            {categorySlugs.map((slug) => {
              const category = facets?.categories.find((item) => item.slug === slug);
              return (
                <FilterChip
                  key={`category-${slug}`}
                  label={category?.name ?? slug}
                  onRemove={() => removeFilterChip("category", slug)}
                />
              );
            })}
            {brandSlugs.map((slug) => {
              const brand = facets?.brands.find((item) => item.slug === slug);
              return (
                <FilterChip
                  key={`brand-${slug}`}
                  label={brand?.name ?? slug}
                  onRemove={() => removeFilterChip("brand", slug)}
                />
              );
            })}
            {(minPrice !== undefined || maxPrice !== undefined) && (
              <FilterChip
                label={`${minPrice ? formatRupiah(minPrice) : "Rp0"} - ${
                  maxPrice ? formatRupiah(maxPrice) : "Maks"
                }`}
                onRemove={() => {
                  const next = new URLSearchParams(sp);
                  next.delete("min_price");
                  next.delete("max_price");
                  next.delete("page");
                  router.push(`/search?${next}`);
                }}
              />
            )}
            {inStock && (
              <FilterChip label="Stok tersedia" onRemove={() => updateParam("in_stock", null)} />
            )}
            {minRating !== undefined && (
              <FilterChip label={`Rating ${minRating}+`} onRemove={() => updateParam("min_rating", null)} />
            )}
            <button
              type="button"
              onClick={resetFilters}
              className="h-7 rounded-full px-2 text-xs font-extrabold text-red-500 active:bg-red-50"
            >
              Reset semua filter
            </button>
          </div>
        )}

        <div className="mt-4 gap-6 md:grid md:grid-cols-[240px_1fr]">
          <aside className="hidden md:block">
            <div className="sticky top-24 max-h-[calc(100vh-6rem)] overflow-y-auto rounded-2xl border border-gray-100 bg-white p-4">
              <h2 className="mb-4 text-sm font-black text-gray-950">Filter</h2>
              <SearchFilters
                facets={facets}
                filters={filters}
                onFiltersChange={applyFilters}
                onReset={resetFilters}
              />
            </div>
          </aside>

          <section className="min-w-0">
            {loading ? (
              <SearchGridSkeleton />
            ) : data && data.items.length === 0 ? (
              <div className="overflow-hidden rounded-2xl border border-gray-100 bg-white">
                <SearchEmptyState
                  query={q}
                  hasActiveFilters={hasActiveFilters}
                  onReset={resetFilters}
                />
              </div>
            ) : data ? (
              <>
                <div className="grid grid-cols-2 gap-2.5 sm:gap-3 lg:grid-cols-3 xl:grid-cols-4">
                  {data.items.map((item, index) => (
                    <SearchProductCard key={item.id} item={item} priority={index < 2} />
                  ))}
                </div>

                {totalPages > 1 && (
                  <Pagination
                    page={page}
                    totalPages={totalPages}
                    onPageChange={(nextPage) => updateParam("page", String(nextPage))}
                  />
                )}
              </>
            ) : null}
          </section>
        </div>
      </div>

      <BottomSheet
        open={sortOpen}
        onClose={() => setSortOpen(false)}
        title="Urutkan Produk"
      >
        <div className="-mx-1 space-y-1">
          {SORT_OPTIONS.map((option) => {
            const selected = option.value === sort;

            return (
              <button
                key={option.value}
                type="button"
                onClick={() => {
                  updateParam("sort", option.value === "relevance" ? null : option.value);
                  setSortOpen(false);
                }}
                className={`flex h-12 w-full items-center justify-between rounded-2xl px-4 text-left text-sm font-extrabold transition active:bg-natalo-50 ${
                  selected ? "bg-natalo-50 text-natalo-700" : "text-gray-800"
                }`}
                style={NON_SELECTABLE_TOUCH_STYLE}
              >
                <span>{option.label}</span>
                {selected && <CheckIcon className="h-5 w-5 text-natalo-600" />}
              </button>
            );
          })}
        </div>
      </BottomSheet>

      <BottomSheet
        open={filterOpen}
        onClose={() => setFilterOpen(false)}
        title="Filter Produk"
        footer={
          <button
            type="button"
            onClick={() => setFilterOpen(false)}
            className="h-11 w-full rounded-full bg-natalo-600 text-sm font-black text-white active:bg-natalo-700"
          >
            Lihat hasil ({data?.total ?? 0})
          </button>
        }
      >
        <SearchFilters
          facets={facets}
          filters={filters}
          onFiltersChange={applyFilters}
          onReset={resetFilters}
        />
      </BottomSheet>
    </div>
  );
}

function SearchResultHeader({ query }: { query: string }) {
  const router = useRouter();
  const sp = useSearchParams();
  const wrapperRef = useRef<HTMLDivElement | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [draft, setDraft] = useState(query);
  const [suggest, setSuggest] = useState<Suggest>(EMPTY_SUGGEST);
  const [suggestOpen, setSuggestOpen] = useState(false);
  const [suggestLoading, setSuggestLoading] = useState(false);

  useEffect(() => {
    setDraft(query);
  }, [query]);

  useEffect(() => {
    const keyword = draft.trim();
    if (keyword.length < 2) {
      setSuggest(EMPTY_SUGGEST);
      setSuggestLoading(false);
      return;
    }

    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      setSuggestLoading(true);
      fetch(`/api/search/suggest?q=${encodeURIComponent(keyword)}&limit=8`, {
        signal: controller.signal,
      })
        .then((response) => response.json())
        .then((json) => setSuggest(json))
        .catch((error) => {
          if (error instanceof Error && error.name === "AbortError") return;
          setSuggest(EMPTY_SUGGEST);
        })
        .finally(() => {
          if (!controller.signal.aborted) setSuggestLoading(false);
        });
    }, 220);

    return () => {
      controller.abort();
      window.clearTimeout(timer);
    };
  }, [draft]);

  useEffect(() => {
    function onPointerDown(event: PointerEvent) {
      if (!wrapperRef.current?.contains(event.target as Node)) {
        setSuggestOpen(false);
      }
    }
    document.addEventListener("pointerdown", onPointerDown);
    return () => document.removeEventListener("pointerdown", onPointerDown);
  }, []);

  function submitSearch(keyword = draft) {
    const trimmed = keyword.trim();
    const keywordChanged = trimmed !== query.trim();
    const next = keywordChanged ? buildKeywordOnlySearchParams(trimmed) : new URLSearchParams(sp);
    if (trimmed) next.set("q", trimmed);
    else next.delete("q");
    next.delete("page");
    setSuggestOpen(false);
    inputRef.current?.blur();
    if (trimmed && keywordChanged) {
      void fetch("/api/search/log", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ keyword: trimmed }),
      }).catch(() => {});
    }
    router.push(`/search?${next}`);
  }

  const hasSuggest =
    suggest.products.length > 0 || suggest.categories.length > 0 || suggest.brands.length > 0;

  return (
    <header
      className="sticky top-0 z-30 border-b border-gray-100 bg-white/95 px-3 pb-3 backdrop-blur md:static md:px-4"
      style={{
        minHeight: "calc(56px + env(safe-area-inset-top))",
        paddingTop: "calc(env(safe-area-inset-top) + 10px)",
      }}
    >
      <div ref={wrapperRef} className="relative mx-auto flex max-w-6xl items-center gap-2">
        <button
          type="button"
          onClick={() => router.back()}
          aria-label="Kembali"
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-gray-700 active:bg-gray-100"
        >
          <BackIcon className="h-5 w-5" />
        </button>

        <form
          onSubmit={(event) => {
            event.preventDefault();
            submitSearch();
          }}
          className="min-w-0 flex-1"
        >
          <div className="flex h-10 items-center rounded-full border border-natalo-200 bg-natalo-50/60 px-3 shadow-sm focus-within:border-natalo-500 focus-within:bg-white focus-within:ring-2 focus-within:ring-natalo-100">
            <SearchIcon className="mr-2 h-4 w-4 shrink-0 text-natalo-500" />
            <input
              ref={inputRef}
              value={draft}
              onChange={(event) => {
                setDraft(event.target.value);
                setSuggestOpen(true);
              }}
              onFocus={() => draft.trim().length >= 2 && setSuggestOpen(true)}
              type="search"
              inputMode="search"
              enterKeyHint="search"
              placeholder="Search produk..."
              className="h-full min-w-0 flex-1 bg-transparent text-sm font-bold text-gray-900 outline-none placeholder:font-semibold placeholder:text-gray-400"
            />
            {draft && (
              <button
                type="button"
                aria-label="Hapus kata kunci"
                onClick={() => {
                  setDraft("");
                  setSuggest(EMPTY_SUGGEST);
                  inputRef.current?.focus();
                }}
                className="ml-2 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-white text-gray-400 active:bg-gray-100"
              >
                <XIcon className="h-4 w-4" />
              </button>
            )}
          </div>
        </form>

        {suggestOpen && draft.trim().length >= 2 && (
          <SuggestionPanel
            query={draft}
            data={suggest}
            loading={suggestLoading}
            hasResults={hasSuggest}
            onPick={submitSearch}
          />
        )}
      </div>
    </header>
  );
}

function SuggestionPanel({
  query,
  data,
  loading,
  hasResults,
  onPick,
}: {
  query: string;
  data: Suggest;
  loading: boolean;
  hasResults: boolean;
  onPick: (keyword: string) => void;
}) {
  return (
    <div className="absolute left-12 right-0 top-full z-40 mt-2 max-h-[70vh] overflow-y-auto rounded-2xl border border-gray-100 bg-white p-2 shadow-xl md:left-12">
      {loading && (
        <div className="px-3 py-3 text-sm font-semibold text-gray-500">Mencari saran...</div>
      )}

      {!loading && !hasResults && (
        <button
          type="button"
          onClick={() => onPick(query)}
          className="flex w-full items-center gap-3 rounded-xl px-3 py-3 text-left text-sm font-bold text-gray-700 active:bg-gray-50"
        >
          <SearchIcon className="h-4 w-4 text-gray-400" />
          Cari "{query.trim()}"
        </button>
      )}

      {!loading && hasResults && (
        <div className="space-y-1">
          {data.brands.map((brand) => (
            <SuggestionRow
              key={`brand-${brand.slug}`}
              label={`Brand: ${brand.name}`}
              meta={`${brand.count} produk`}
              onClick={() => onPick(brand.name)}
            />
          ))}
          {data.categories.map((category) => (
            <SuggestionRow
              key={`category-${category.slug}`}
              label={`Kategori: ${category.name}`}
              meta={`${category.count} produk`}
              onClick={() => onPick(category.name)}
            />
          ))}
          {data.products.map((product) => (
            <SuggestionRow
              key={product.id}
              label={product.name}
              meta={product.brand_name ?? "Produk"}
              onClick={() => onPick(product.name)}
            />
          ))}
          <button
            type="button"
            onClick={() => onPick(query)}
            className="mt-1 flex w-full items-center justify-center rounded-xl bg-natalo-50 px-3 py-2.5 text-sm font-black text-natalo-700 active:bg-natalo-100"
          >
            Lihat semua hasil "{query.trim()}"
          </button>
        </div>
      )}
    </div>
  );
}

function SuggestionRow({
  label,
  meta,
  onClick,
}: {
  label: string;
  meta: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left active:bg-gray-50"
    >
      <SearchIcon className="h-4 w-4 shrink-0 text-gray-400" />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-bold text-gray-900">{label}</span>
        <span className="block truncate text-xs font-semibold text-gray-400">{meta}</span>
      </span>
    </button>
  );
}

function SearchProductCard({ item, priority }: { item: SearchItem; priority?: boolean }) {
  const href = `/products/${item.slug}`;
  const displayPrice =
    item.discount_price !== null && item.discount_price < item.price_min
      ? item.discount_price
      : item.price_min;
  const priceLabel =
    item.price_min === item.price_max
      ? formatRupiah(displayPrice)
      : `Mulai ${formatRupiah(displayPrice)}`;
  const outOfStock = item.total_stock <= 0;
  const label = item.brand_name ?? item.category_name ?? "Natalo Petshop";

  return (
    <article className="group relative flex min-w-0 flex-col overflow-hidden rounded-xl border border-gray-100 bg-white shadow-sm transition active:scale-[0.99] md:hover:shadow-md">
      <Link href={href} className="flex min-w-0 flex-1 flex-col">
        <div className="relative aspect-square overflow-hidden bg-gray-100">
          {item.image_url ? (
            <Image
              src={item.image_url}
              alt={item.name}
              fill
              priority={priority}
              sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 25vw"
              placeholder="blur"
              blurDataURL={IMAGE_BLUR_GRAY}
              className="object-cover transition duration-300 group-hover:scale-105"
            />
          ) : (
            <div className="flex h-full w-full items-center justify-center text-3xl font-black text-gray-200">
              NP
            </div>
          )}
          <span
            className={`absolute left-2 top-2 rounded-full px-2 py-0.5 text-[10px] font-black ${
              outOfStock ? "bg-gray-900/80 text-white" : "bg-emerald-500 text-white"
            }`}
          >
            {outOfStock ? "Habis" : "Tersedia"}
          </span>
        </div>

        <div className="flex min-w-0 flex-1 flex-col p-2.5">
          <p className="truncate text-[10px] font-black uppercase tracking-wide text-natalo-500">
            {label}
          </p>
          <h2 className="mt-1 line-clamp-2 min-h-[2.35rem] text-xs font-bold leading-snug text-gray-900 md:text-sm">
            {item.name}
          </h2>
          <div className="mt-2">
            <p className="truncate text-sm font-black leading-tight text-natalo-600 md:text-base">
              {priceLabel}
            </p>
            {item.review_count > 0 && (
              <p className="mt-0.5 text-[11px] font-semibold text-gray-400">
                Rating {item.avg_rating.toFixed(1)} ({item.review_count})
              </p>
            )}
          </div>
        </div>
      </Link>

      <div className="px-2.5 pb-2.5">
        <QuickAddToCart
          product={{
            id: item.id,
            slug: item.slug,
            name: item.name,
            price: item.price_min,
            discountPrice: item.discount_price,
            stock: item.stock ?? item.total_stock,
            weightGram: item.weight_grams,
            imageUrl: item.image_url,
            isActive: item.is_active,
            hasVariants: item.has_variants,
          }}
          className="h-8 py-0 text-[11px]"
        />
      </div>
    </article>
  );
}

function SearchGridSkeleton() {
  return (
    <div className="grid grid-cols-2 gap-2.5 sm:gap-3 lg:grid-cols-3 xl:grid-cols-4">
      {Array.from({ length: 8 }).map((_, index) => (
        <div key={index} className="overflow-hidden rounded-xl border border-gray-100 bg-white">
          <div className="aspect-square animate-pulse bg-gray-100" />
          <div className="space-y-2 p-2.5">
            <div className="h-2.5 w-16 animate-pulse rounded bg-gray-100" />
            <div className="h-3 w-full animate-pulse rounded bg-gray-100" />
            <div className="h-3 w-4/5 animate-pulse rounded bg-gray-100" />
            <div className="h-4 w-20 animate-pulse rounded bg-gray-100" />
            <div className="h-8 w-full animate-pulse rounded-full bg-gray-100" />
          </div>
        </div>
      ))}
    </div>
  );
}

function SearchEmptyState({
  query,
  hasActiveFilters,
  onReset,
}: {
  query: string;
  hasActiveFilters: boolean;
  onReset: () => void;
}) {
  const suggestions = ["royal canin", "kandang besi", "makanan kucing", "filter aquarium"];

  return (
    <div className="flex flex-col items-center justify-center px-5 py-12 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-natalo-50 text-lg font-black text-natalo-600">
        NP
      </div>
      <h2 className="mt-4 text-base font-black text-gray-950">
        {hasActiveFilters ? "Produk tidak ditemukan karena filter aktif" : "Produk tidak ditemukan"}
      </h2>
      <p className="mt-1 max-w-xs text-sm leading-6 text-gray-500">
        {hasActiveFilters
          ? "Hapus beberapa filter atau reset semua filter untuk melihat produk yang cocok."
          : query
            ? `Tidak ada produk untuk "${query}". Coba gunakan kata kunci lain atau cek kategori produk.`
            : "Coba gunakan kata kunci lain atau cek kategori produk."}
      </p>
      <div className="mt-5 flex flex-wrap justify-center gap-2">
        {hasActiveFilters ? (
          <button
            type="button"
            onClick={onReset}
            className="rounded-full bg-natalo-600 px-4 py-2 text-xs font-black text-white active:bg-natalo-700"
          >
            Reset semua filter
          </button>
        ) : (
          suggestions.map((suggestion) => (
            <Link
              key={suggestion}
              href={`/search?q=${encodeURIComponent(suggestion)}`}
              className="rounded-full border border-gray-200 bg-white px-3 py-2 text-xs font-black text-gray-700 active:bg-gray-50"
            >
              {suggestion}
            </Link>
          ))
        )}
      </div>
    </div>
  );
}

function FilterChip({ label, onRemove }: { label: string; onRemove: () => void }) {
  return (
    <button
      type="button"
      onClick={onRemove}
      className="inline-flex h-7 max-w-full items-center gap-1 rounded-full bg-natalo-50 px-2.5 text-xs font-extrabold text-natalo-700 active:bg-natalo-100"
    >
      <span className="truncate">{label}</span>
      <XIcon className="h-3.5 w-3.5 shrink-0" />
    </button>
  );
}

function Pagination({
  page,
  totalPages,
  onPageChange,
}: {
  page: number;
  totalPages: number;
  onPageChange: (page: number) => void;
}) {
  return (
    <nav className="mt-6 flex items-center justify-center gap-2">
      <button
        type="button"
        onClick={() => onPageChange(page - 1)}
        disabled={page <= 1}
        className="h-9 rounded-full border border-gray-200 bg-white px-3 text-xs font-black text-gray-700 disabled:cursor-not-allowed disabled:opacity-40"
      >
        Prev
      </button>
      <span className="rounded-full bg-white px-3 py-2 text-xs font-black text-gray-500">
        {page} / {totalPages}
      </span>
      <button
        type="button"
        onClick={() => onPageChange(page + 1)}
        disabled={page >= totalPages}
        className="h-9 rounded-full border border-gray-200 bg-white px-3 text-xs font-black text-gray-700 disabled:cursor-not-allowed disabled:opacity-40"
      >
        Next
      </button>
    </nav>
  );
}

function SearchIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className={className} aria-hidden>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.5-3.5" />
    </svg>
  );
}

function BackIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" className={className} aria-hidden>
      <path d="m15 18-6-6 6-6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function XIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" className={className} aria-hidden>
      <path d="M18 6 6 18" strokeLinecap="round" />
      <path d="m6 6 12 12" strokeLinecap="round" />
    </svg>
  );
}

function FilterIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className={className} aria-hidden>
      <path d="M4 6h16" strokeLinecap="round" />
      <path d="M7 12h10" strokeLinecap="round" />
      <path d="M10 18h4" strokeLinecap="round" />
    </svg>
  );
}

function ChevronDownIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className={className} aria-hidden>
      <path d="m6 9 6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function CheckIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" className={className} aria-hidden>
      <path d="m5 12 4 4 10-10" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export default function SearchPage() {
  return (
    <Suspense
      fallback={
        <div className="mx-auto max-w-6xl px-3 py-4 md:px-4">
          <SearchGridSkeleton />
        </div>
      }
    >
      <SearchPageContent />
    </Suspense>
  );
}
