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

const TRENDING_PRODUCTS: { q: string; emoji: string; bg: string; title: string; reason: string }[] = [
  {
    q: "royal canin persian",
    emoji: "🐾",
    bg: "linear-gradient(135deg,#fef3c7,#fed7aa)",
    title: "Royal Canin Persian Adult 2 kg",
    reason: "+248% pencarian · 30% off",
  },
  {
    q: "angels creamy tuna",
    emoji: "🐱",
    bg: "linear-gradient(135deg,#fce7f3,#fbcfe8)",
    title: "Angels Creamy Tuna pack 12",
    reason: "Jadi camilan favorit · review 5⭐",
  },
  {
    q: "cat litter tofu",
    emoji: "🌾",
    bg: "linear-gradient(135deg,#fee2e2,#fecaca)",
    title: "Cat Litter Tofu Strawberry 6L",
    reason: "Eco-friendly · wangi tahan lama",
  },
];

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
    /* ignore quota / serialization errors */
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
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!open) return;
    setHistory(loadHistory());
    const t = window.setTimeout(() => inputRef.current?.focus(), 60);
    document.body.style.overflow = "hidden";

    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);

    return () => {
      window.clearTimeout(t);
      document.body.style.overflow = "";
      window.removeEventListener("keydown", onKey);
    };
  }, [open, onClose]);

  function commit(q: string) {
    const trimmed = q.trim();
    if (!trimmed) return;

    const next = [trimmed, ...history.filter((h) => h !== trimmed)].slice(0, MAX_HISTORY);
    setHistory(next);
    saveHistory(next);

    onClose();
    router.push(`/search?q=${encodeURIComponent(trimmed)}`);
  }

  function removeHistoryItem(q: string) {
    const next = history.filter((h) => h !== q);
    setHistory(next);
    saveHistory(next);
  }

  function clearAllHistory() {
    setHistory([]);
    saveHistory([]);
  }

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[80] flex flex-col bg-white nat-search-slide">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          commit(query);
        }}
        className="flex items-center gap-2 border-b border-zinc-100 bg-white px-3 py-2.5"
      >
        <button
          type="button"
          onClick={onClose}
          aria-label="Tutup pencarian"
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-zinc-700 hover:bg-zinc-100"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="h-4 w-4"
            aria-hidden
          >
            <path d="m15 6-6 6 6 6" />
          </svg>
        </button>
        <div className="flex flex-1 items-center gap-2 rounded-full border border-orange-300 bg-white px-4 py-2.5 shadow-sm focus-within:border-orange-500 focus-within:ring-2 focus-within:ring-orange-100">
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="h-4 w-4 shrink-0 text-zinc-400"
            aria-hidden
          >
            <circle cx="11" cy="11" r="7" />
            <path d="m20 20-3.5-3.5" />
          </svg>
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Cari produk, brand, atau kategori..."
            autoComplete="off"
            spellCheck={false}
            className="flex-1 bg-transparent text-sm outline-none placeholder:text-zinc-400"
          />
          {query && (
            <button
              type="button"
              onClick={() => {
                setQuery("");
                inputRef.current?.focus();
              }}
              aria-label="Hapus kata kunci"
              className="flex h-6 w-6 items-center justify-center rounded-full bg-zinc-100 text-xs font-bold text-zinc-500 hover:bg-zinc-200"
            >
              ×
            </button>
          )}
        </div>
      </form>

      <div className="flex-1 overflow-y-auto px-4 pb-8">
        {history.length > 0 && (
          <section className="pt-4">
            <div className="flex items-center justify-between">
              <h4 className="text-sm font-bold text-zinc-900">🕓 Pencarian terakhir</h4>
              <button
                type="button"
                onClick={clearAllHistory}
                className="text-xs font-bold text-orange-600 hover:underline"
              >
                Hapus semua
              </button>
            </div>
            <ul className="mt-2 divide-y divide-zinc-100">
              {history.map((h) => (
                <li key={h} className="flex items-center gap-3 py-2.5">
                  <button
                    type="button"
                    onClick={() => commit(h)}
                    className="flex flex-1 items-center gap-3 text-left"
                  >
                    <span className="text-base text-zinc-400" aria-hidden>
                      🕓
                    </span>
                    <span className="flex-1 truncate text-sm text-zinc-700">{h}</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => removeHistoryItem(h)}
                    aria-label={`Hapus ${h} dari riwayat`}
                    className="flex h-7 w-7 items-center justify-center rounded-full text-zinc-400 hover:bg-zinc-100 hover:text-zinc-600"
                  >
                    ×
                  </button>
                </li>
              ))}
            </ul>
          </section>
        )}

        <section className="pt-5">
          <h4 className="text-sm font-bold text-zinc-900">🔥 Pencarian populer minggu ini</h4>
          <div className="mt-3 flex flex-wrap gap-2">
            {POPULAR_QUERIES.map((p) => (
              <button
                key={p.q}
                type="button"
                onClick={() => commit(p.q)}
                className="inline-flex items-center gap-1.5 rounded-full border border-orange-200 bg-orange-50 px-3 py-1.5 text-xs font-bold text-orange-900 hover:border-orange-300 hover:bg-orange-100"
              >
                <span className="font-black text-orange-600">#{p.rank}</span>
                <span>{p.q}</span>
              </button>
            ))}
          </div>
        </section>

        <section className="pt-6">
          <h4 className="text-sm font-bold text-zinc-900">📈 Lagi trending</h4>
          <ul className="mt-3 space-y-2">
            {TRENDING_PRODUCTS.map((t) => (
              <li key={t.q}>
                <button
                  type="button"
                  onClick={() => commit(t.q)}
                  className="flex w-full items-center gap-3 rounded-2xl border border-zinc-100 bg-white p-3 text-left hover:border-orange-200 hover:bg-orange-50/50"
                >
                  <span
                    aria-hidden
                    className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl text-xl"
                    style={{ background: t.bg }}
                  >
                    {t.emoji}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-bold text-zinc-900">
                      {t.title}
                    </span>
                    <span className="block truncate text-[11px] text-zinc-500">{t.reason}</span>
                  </span>
                  <span aria-hidden className="text-lg text-zinc-300">
                    ›
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </div>
  );
}
