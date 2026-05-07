"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { formatRupiah } from "@/lib/format";

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

const EMPTY: Suggest = { products: [], categories: [], brands: [], total: 0 };

export function SearchBar() {
  const router = useRouter();
  const [q, setQ] = useState("");
  const [data, setData] = useState<Suggest>(EMPTY);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const [activeIdx, setActiveIdx] = useState(-1); // keyboard nav
  const inputRef = useRef<HTMLInputElement>(null);
  const wrapperRef = useRef<HTMLDivElement>(null);

  // Debounce fetch suggest
  useEffect(() => {
    if (q.trim().length < 2) {
      setData(EMPTY);
      return;
    }
    const t = setTimeout(async () => {
      setLoading(true);
      try {
        const res = await fetch(
          `/api/search/suggest?q=${encodeURIComponent(q.trim())}&limit=5`
        );
        const json = (await res.json()) as Suggest;
        setData(json);
      } catch {
        setData(EMPTY);
      } finally {
        setLoading(false);
      }
    }, 300);
    return () => clearTimeout(t);
  }, [q]);

  // Click outside → close
  useEffect(() => {
    function handler(e: MouseEvent) {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  // Build flat list untuk keyboard nav
  const flatItems: Array<{ type: "product" | "category" | "brand"; href: string; label: string }> =
    [
      ...data.products.map((p) => ({
        type: "product" as const,
        href: `/products/${p.slug}`,
        label: p.name,
      })),
      ...data.categories.map((c) => ({
        type: "category" as const,
        href: `/search?q=${encodeURIComponent(q)}&category=${c.slug}`,
        label: c.name,
      })),
      ...data.brands.map((b) => ({
        type: "brand" as const,
        href: `/search?q=${encodeURIComponent(q)}&brand=${b.slug}`,
        label: b.name,
      })),
    ];

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActiveIdx((i) => Math.min(i + 1, flatItems.length - 1));
      setOpen(true);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActiveIdx((i) => Math.max(i - 1, -1));
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (activeIdx >= 0 && flatItems[activeIdx]) {
        router.push(flatItems[activeIdx].href);
      } else if (q.trim()) {
        router.push(`/search?q=${encodeURIComponent(q.trim())}`);
      }
      setOpen(false);
      setActiveIdx(-1);
      inputRef.current?.blur();
    } else if (e.key === "Escape") {
      setOpen(false);
      setActiveIdx(-1);
      inputRef.current?.blur();
    }
  }

  function highlight(text: string, query: string) {
    if (!query.trim()) return text;
    const regex = new RegExp(
      `(${query.trim().replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`,
      "gi"
    );
    const parts = text.split(regex);
    return parts.map((part, i) =>
      regex.test(part) ? (
        <strong key={i} className="font-bold text-natalo-700">
          {part}
        </strong>
      ) : (
        <span key={i}>{part}</span>
      )
    );
  }

  const hasResults =
    data.products.length > 0 || data.categories.length > 0 || data.brands.length > 0;
  let runningIdx = -1;

  return (
    <div ref={wrapperRef} className="relative w-full">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (q.trim()) {
            router.push(`/search?q=${encodeURIComponent(q.trim())}`);
            setOpen(false);
            inputRef.current?.blur();
          }
        }}
      >
        <div className="relative">
          <input
            ref={inputRef}
            type="search"
            value={q}
            onChange={(e) => {
              setQ(e.target.value);
              setOpen(true);
              setActiveIdx(-1);
            }}
            onFocus={() => q.trim().length >= 2 && setOpen(true)}
            onKeyDown={handleKeyDown}
            placeholder="🔍 Cari produk, brand, atau kategori..."
            className="w-full rounded-full border border-zinc-200 bg-white px-5 py-2.5 pr-10 text-sm outline-none transition focus:border-natalo-400 focus:ring-2 focus:ring-natalo-100"
            autoComplete="off"
          />
          {loading && (
            <span className="absolute right-4 top-1/2 -translate-y-1/2 text-xs text-zinc-400">
              ⏳
            </span>
          )}
        </div>
      </form>

      {/* Dropdown */}
      {open && q.trim().length >= 2 && (
        <div className="absolute left-0 right-0 top-full z-40 mt-2 max-h-[80vh] overflow-y-auto rounded-2xl border border-zinc-200 bg-white shadow-xl">
          {!hasResults && !loading ? (
            <div className="p-4 text-center text-sm text-zinc-500">
              Tidak ada hasil untuk &ldquo;{q}&rdquo;
            </div>
          ) : (
            <>
              {/* Products */}
              {data.products.length > 0 && (
                <div className="border-b border-zinc-100 p-2">
                  <p className="px-2 py-1 text-[10px] font-bold uppercase tracking-wider text-zinc-400">
                    Produk
                  </p>
                  {data.products.map((p) => {
                    runningIdx++;
                    const isActive = runningIdx === activeIdx;
                    return (
                      <button
                        key={p.id}
                        type="button"
                        onClick={() => {
                          router.push(`/products/${p.slug}`);
                          setOpen(false);
                        }}
                        className={`flex w-full items-center gap-3 rounded-lg p-2 text-left transition ${
                          isActive ? "bg-natalo-50" : "hover:bg-zinc-50"
                        }`}
                      >
                        <div className="h-10 w-10 shrink-0 overflow-hidden rounded-lg bg-zinc-100">
                          {p.image_url ? (
                            // eslint-disable-next-line @next/next/no-img-element
                            <img
                              src={p.image_url}
                              alt={p.name}
                              className="h-full w-full object-cover"
                            />
                          ) : (
                            <div className="flex h-full items-center justify-center text-base">
                              🐾
                            </div>
                          )}
                        </div>
                        <div className="min-w-0 flex-1">
                          {p.brand_name && (
                            <p className="text-[10px] font-bold uppercase tracking-wider text-purple-500">
                              {p.brand_name}
                            </p>
                          )}
                          <p className="truncate text-sm text-zinc-900">
                            {highlight(p.name, q)}
                          </p>
                        </div>
                        <p className="shrink-0 text-xs font-bold text-natalo-600">
                          {p.price_min === p.price_max
                            ? formatRupiah(p.price_min)
                            : `dari ${formatRupiah(p.price_min)}`}
                        </p>
                      </button>
                    );
                  })}
                </div>
              )}

              {/* Categories */}
              {data.categories.length > 0 && (
                <div className="border-b border-zinc-100 p-2">
                  <p className="px-2 py-1 text-[10px] font-bold uppercase tracking-wider text-zinc-400">
                    Kategori
                  </p>
                  {data.categories.map((c) => {
                    runningIdx++;
                    const isActive = runningIdx === activeIdx;
                    return (
                      <button
                        key={c.slug}
                        type="button"
                        onClick={() => {
                          router.push(
                            `/search?q=${encodeURIComponent(q)}&category=${c.slug}`
                          );
                          setOpen(false);
                        }}
                        className={`flex w-full items-center justify-between rounded-lg p-2 text-left transition ${
                          isActive ? "bg-natalo-50" : "hover:bg-zinc-50"
                        }`}
                      >
                        <span className="text-sm">📁 {highlight(c.name, q)}</span>
                        <span className="text-xs text-zinc-400">{c.count}</span>
                      </button>
                    );
                  })}
                </div>
              )}

              {/* Brands */}
              {data.brands.length > 0 && (
                <div className="border-b border-zinc-100 p-2">
                  <p className="px-2 py-1 text-[10px] font-bold uppercase tracking-wider text-zinc-400">
                    Brand
                  </p>
                  {data.brands.map((b) => {
                    runningIdx++;
                    const isActive = runningIdx === activeIdx;
                    return (
                      <button
                        key={b.slug}
                        type="button"
                        onClick={() => {
                          router.push(
                            `/search?q=${encodeURIComponent(q)}&brand=${b.slug}`
                          );
                          setOpen(false);
                        }}
                        className={`flex w-full items-center justify-between rounded-lg p-2 text-left transition ${
                          isActive ? "bg-natalo-50" : "hover:bg-zinc-50"
                        }`}
                      >
                        <span className="text-sm">🏭 {highlight(b.name, q)}</span>
                        <span className="text-xs text-zinc-400">{b.count}</span>
                      </button>
                    );
                  })}
                </div>
              )}

              {/* Lihat semua hasil */}
              <button
                type="button"
                onClick={() => {
                  router.push(`/search?q=${encodeURIComponent(q.trim())}`);
                  setOpen(false);
                }}
                className="block w-full p-3 text-center text-sm font-bold text-natalo-700 hover:bg-natalo-50"
              >
                Lihat semua hasil &ldquo;{q}&rdquo; →
              </button>
            </>
          )}
        </div>
      )}
    </div>
  );
}
