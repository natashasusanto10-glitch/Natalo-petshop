"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";

const STORAGE_KEY = "nat-search-history";
const MAX_HISTORY = 6;

const POPULAR_QUERIES: { rank: number; q: string }[] = [
  { rank: 1, q: "angels creamy" },
  { rank: 2, q: "royal canin" },
  { rank: 3, q: "grooming kucing" },
  { rank: 4, q: "kandang besi" },
  { rank: 5, q: "vitamin bulu" },
  { rank: 6, q: "susu kucing" },
  { rank: 7, q: "filter aquarium" },
  { rank: 8, q: "tali leash" },
];

const TRENDING_PRODUCTS: { q: string; title: string; reason: string }[] = [
  {
    q: "royal canin persian",
    title: "Royal Canin Persian Adult",
    reason: "Sering dicari untuk kucing ras",
  },
  {
    q: "angels creamy tuna",
    title: "Angels Creamy Tuna",
    reason: "Camilan kucing favorit",
  },
  {
    q: "cat litter tofu",
    title: "Cat Litter Tofu",
    reason: "Pasir kucing praktis dan wangi",
  },
];

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

const EMPTY_SUGGEST: Suggest = {
  products: [],
  categories: [],
  brands: [],
  total: 0,
};

function loadHistory(): string[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((q): q is string => typeof q === "string") : [];
  } catch {
    return [];
  }
}

function saveHistory(history: string[]) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(history.slice(0, MAX_HISTORY)));
  } catch {
    // Ignore storage quota or private-mode failures.
  }
}

type Props = {
  open: boolean;
  onClose: () => void;
};

export function SearchOverlay({ open, onClose }: Props) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [history, setHistory] = useState<string[]>([]);
  const [suggest, setSuggest] = useState<Suggest>(EMPTY_SUGGEST);
  const [suggestLoading, setSuggestLoading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!open) return;
    setHistory(loadHistory());
    const timer = window.setTimeout(() => inputRef.current?.focus(), 60);
    const originalOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    document.body.classList.add("nat-modal-open");

    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);

    return () => {
      window.clearTimeout(timer);
      document.body.style.overflow = originalOverflow;
      document.body.classList.remove("nat-modal-open");
      window.removeEventListener("keydown", onKey);
    };
  }, [open, onClose]);

  useEffect(() => {
    const keyword = query.trim();
    if (!open || keyword.length < 2) {
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
  }, [open, query]);

  function commit(value: string) {
    const trimmed = value.trim();
    if (!trimmed) return;

    const next = [trimmed, ...history.filter((item) => item !== trimmed)].slice(0, MAX_HISTORY);
    setHistory(next);
    saveHistory(next);
    setQuery("");
    setSuggest(EMPTY_SUGGEST);

    onClose();
    router.push(`/search?q=${encodeURIComponent(trimmed)}`);
  }

  function removeHistoryItem(value: string) {
    const next = history.filter((item) => item !== value);
    setHistory(next);
    saveHistory(next);
  }

  function clearAllHistory() {
    setHistory([]);
    saveHistory([]);
  }

  if (!open) return null;

  const hasSuggestions =
    suggest.products.length > 0 || suggest.categories.length > 0 || suggest.brands.length > 0;

  return (
    <div className="fixed inset-0 z-[9999] flex flex-col bg-white">
      <form
        onSubmit={(event) => {
          event.preventDefault();
          commit(query);
        }}
        className="flex items-center gap-2 border-b border-gray-100 bg-white px-3 py-2.5"
        style={{ paddingTop: "max(0.625rem, env(safe-area-inset-top))" }}
      >
        <button
          type="button"
          onClick={onClose}
          aria-label="Tutup pencarian"
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-gray-700 active:bg-gray-100"
        >
          <BackIcon className="h-5 w-5" />
        </button>

        <div className="flex h-10 flex-1 items-center gap-2 rounded-full border border-natalo-200 bg-natalo-50/60 px-3 shadow-sm focus-within:border-natalo-500 focus-within:bg-white focus-within:ring-2 focus-within:ring-natalo-100">
          <SearchIcon className="h-4 w-4 shrink-0 text-natalo-500" />
          <input
            ref={inputRef}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Cari produk, brand, atau kategori..."
            autoComplete="off"
            spellCheck={false}
            type="search"
            inputMode="search"
            enterKeyHint="search"
            className="h-full min-w-0 flex-1 bg-transparent text-sm font-bold text-gray-900 outline-none placeholder:font-semibold placeholder:text-gray-400"
          />
          {query && (
            <button
              type="button"
              onClick={() => {
                setQuery("");
                setSuggest(EMPTY_SUGGEST);
                inputRef.current?.focus();
              }}
              aria-label="Hapus kata kunci"
              className="flex h-6 w-6 items-center justify-center rounded-full bg-white text-gray-400 active:bg-gray-100"
            >
              <XIcon className="h-4 w-4" />
            </button>
          )}
        </div>
      </form>

      <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-8">
        {query.trim().length >= 2 && (
          <section className="pt-3">
            <h4 className="text-xs font-black uppercase tracking-wide text-gray-400">
              Saran pencarian
            </h4>
            <div className="mt-2 overflow-hidden rounded-2xl border border-gray-100 bg-white">
              {suggestLoading && (
                <div className="px-3 py-3 text-sm font-semibold text-gray-500">
                  Mencari saran...
                </div>
              )}

              {!suggestLoading && !hasSuggestions && (
                <button
                  type="button"
                  onClick={() => commit(query)}
                  className="flex w-full items-center gap-3 px-3 py-3 text-left text-sm font-bold text-gray-800 active:bg-gray-50"
                >
                  <SearchIcon className="h-4 w-4 text-gray-400" />
                  Cari "{query.trim()}"
                </button>
              )}

              {!suggestLoading && hasSuggestions && (
                <div className="divide-y divide-gray-50">
                  {suggest.brands.map((brand) => (
                    <SuggestionButton
                      key={`brand-${brand.slug}`}
                      title={`Brand: ${brand.name}`}
                      subtitle={`${brand.count} produk`}
                      onClick={() => commit(brand.name)}
                    />
                  ))}
                  {suggest.categories.map((category) => (
                    <SuggestionButton
                      key={`category-${category.slug}`}
                      title={`Kategori: ${category.name}`}
                      subtitle={`${category.count} produk`}
                      onClick={() => commit(category.name)}
                    />
                  ))}
                  {suggest.products.map((product) => (
                    <SuggestionButton
                      key={product.id}
                      title={product.name}
                      subtitle={product.brand_name ?? "Produk"}
                      onClick={() => commit(product.name)}
                    />
                  ))}
                </div>
              )}
            </div>
          </section>
        )}

        {history.length > 0 && (
          <section className="pt-5">
            <div className="flex items-center justify-between">
              <h4 className="text-sm font-black text-gray-900">Pencarian terakhir</h4>
              <button
                type="button"
                onClick={clearAllHistory}
                className="text-xs font-black text-natalo-600 active:text-natalo-700"
              >
                Hapus semua
              </button>
            </div>
            <ul className="mt-2 divide-y divide-gray-100">
              {history.map((item) => (
                <li key={item} className="flex items-center gap-3 py-2.5">
                  <button
                    type="button"
                    onClick={() => commit(item)}
                    className="flex min-w-0 flex-1 items-center gap-3 text-left"
                  >
                    <ClockIcon className="h-4 w-4 shrink-0 text-gray-300" />
                    <span className="flex-1 truncate text-sm font-semibold text-gray-700">
                      {item}
                    </span>
                  </button>
                  <button
                    type="button"
                    onClick={() => removeHistoryItem(item)}
                    aria-label={`Hapus ${item} dari riwayat`}
                    className="flex h-7 w-7 items-center justify-center rounded-full text-gray-400 active:bg-gray-100"
                  >
                    <XIcon className="h-4 w-4" />
                  </button>
                </li>
              ))}
            </ul>
          </section>
        )}

        <section className="pt-5">
          <h4 className="text-sm font-black text-gray-900">Pencarian populer</h4>
          <div className="mt-3 flex flex-wrap gap-2">
            {POPULAR_QUERIES.map((item) => (
              <button
                key={item.q}
                type="button"
                onClick={() => commit(item.q)}
                className="inline-flex items-center gap-1.5 rounded-full border border-natalo-200 bg-natalo-50 px-3 py-1.5 text-xs font-black text-natalo-900 active:bg-natalo-100"
              >
                <span className="text-natalo-600">#{item.rank}</span>
                <span>{item.q}</span>
              </button>
            ))}
          </div>
        </section>

        <section className="pt-6">
          <h4 className="text-sm font-black text-gray-900">Lagi banyak dicari</h4>
          <ul className="mt-3 space-y-2">
            {TRENDING_PRODUCTS.map((item) => (
              <li key={item.q}>
                <button
                  type="button"
                  onClick={() => commit(item.q)}
                  className="flex w-full items-center gap-3 rounded-2xl border border-gray-100 bg-white p-3 text-left active:border-natalo-200 active:bg-natalo-50"
                >
                  <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-natalo-50 text-sm font-black text-natalo-600">
                    NP
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-black text-gray-900">
                      {item.title}
                    </span>
                    <span className="block truncate text-xs font-semibold text-gray-500">
                      {item.reason}
                    </span>
                  </span>
                  <ChevronRightIcon className="h-5 w-5 text-gray-300" />
                </button>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </div>
  );
}

function SuggestionButton({
  title,
  subtitle,
  onClick,
}: {
  title: string;
  subtitle: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center gap-3 px-3 py-2.5 text-left active:bg-gray-50"
    >
      <SearchIcon className="h-4 w-4 shrink-0 text-gray-400" />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-bold text-gray-900">{title}</span>
        <span className="block truncate text-xs font-semibold text-gray-400">{subtitle}</span>
      </span>
    </button>
  );
}

function SearchIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className={className} aria-hidden>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.5-3.5" strokeLinecap="round" />
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

function ClockIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className={className} aria-hidden>
      <circle cx="12" cy="12" r="8" />
      <path d="M12 8v4l3 2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function ChevronRightIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className={className} aria-hidden>
      <path d="m9 18 6-6-6-6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
