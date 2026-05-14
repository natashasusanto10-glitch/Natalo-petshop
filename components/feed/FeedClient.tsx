"use client";

/**
 * Feed client component — fetch + render list, manage active video, tab
 * switching, infinite scroll, comment sheet.
 *
 * Spec compliance:
 * - 3 tabs (Rekomendasi / Promo / Komunitas) — Komunitas DISABLED di MVP
 *   (admin-only content sampai F4/F5 ready)
 * - Pagination 10 per load
 * - Single autoplay (via FeedActiveVideoProvider context wrapping)
 * - Comment di-load saat tap (lazy)
 *
 * MVP gracefully degrades:
 * - Loading skeleton saat fetch awal
 * - Empty state per tab
 * - Retry button kalau error
 */
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { FeedPostTab } from "@prisma/client";
import type { FeedListResponse, FeedPostListItem } from "@/lib/feed/types";
import { hapticTap } from "@/lib/native/haptics";
import { FeedActiveVideoProvider } from "./FeedActiveVideoContext";
import { FeedVideoCard } from "./FeedVideoCard";
import { FeedCommentSheet } from "./FeedCommentSheet";

const TABS: { value: FeedPostTab; label: string; enabled: boolean }[] = [
  { value: "REKOMENDASI", label: "Rekomendasi", enabled: true },
  { value: "PROMO", label: "Promo", enabled: true },
  // Komunitas disabled di MVP — buka setelah F4 (user upload) ready.
  { value: "KOMUNITAS", label: "Komunitas", enabled: false },
];

export function FeedClient() {
  const [activeTab, setActiveTab] = useState<FeedPostTab>("REKOMENDASI");
  const [posts, setPosts] = useState<FeedPostListItem[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [commentPostId, setCommentPostId] = useState<string | null>(null);
  const sentinelRef = useRef<HTMLDivElement>(null);

  // Fetch awal saat tab berubah
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setPosts([]);
    setCursor(null);
    setError(null);
    fetch(`/api/feed/posts?tab=${activeTab}`)
      .then((r) => {
        if (!r.ok) throw new Error("Gagal memuat feed");
        return r.json() as Promise<FeedListResponse>;
      })
      .then((data) => {
        if (cancelled) return;
        setPosts(data.items);
        setCursor(data.nextCursor);
        setHasMore(Boolean(data.nextCursor));
      })
      .catch((err) => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : "Gagal memuat");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [activeTab]);

  const loadMore = useCallback(async () => {
    if (!cursor || loadingMore || !hasMore) return;
    setLoadingMore(true);
    try {
      const res = await fetch(`/api/feed/posts?tab=${activeTab}&cursor=${cursor}`);
      if (!res.ok) throw new Error();
      const data: FeedListResponse = await res.json();
      setPosts((prev) => [...prev, ...data.items]);
      setCursor(data.nextCursor);
      setHasMore(Boolean(data.nextCursor));
    } catch {
      // silent — sentinel akan trigger lagi saat user scroll
    } finally {
      setLoadingMore(false);
    }
  }, [activeTab, cursor, hasMore, loadingMore]);

  // IntersectionObserver untuk infinite scroll sentinel
  useEffect(() => {
    const el = sentinelRef.current;
    if (!el || !hasMore) return;
    const obs = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) loadMore();
        }
      },
      { rootMargin: "400px" },
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, [loadMore, hasMore]);

  function handleSelectTab(tab: FeedPostTab) {
    if (tab === activeTab) return;
    hapticTap();
    setActiveTab(tab);
  }

  const commentSheetOpen = useMemo(() => commentPostId !== null, [commentPostId]);

  return (
    <FeedActiveVideoProvider>
      <div className="mx-auto flex max-w-2xl flex-col gap-4 pb-24 pt-2">
        {/* Tab switcher */}
        <nav
          role="tablist"
          aria-label="Tab Feed"
          className="sticky top-0 z-10 mx-2 flex items-center gap-1 rounded-full border border-gray-100 bg-white/95 p-1 shadow-sm backdrop-blur"
        >
          {TABS.map((t) => (
            <button
              key={t.value}
              type="button"
              role="tab"
              aria-selected={activeTab === t.value}
              disabled={!t.enabled}
              onClick={() => t.enabled && handleSelectTab(t.value)}
              className={`flex-1 rounded-full py-2 text-xs font-extrabold transition ${
                activeTab === t.value
                  ? "bg-natalo-600 text-white shadow-sm"
                  : t.enabled
                    ? "text-gray-600 active:bg-gray-100"
                    : "cursor-not-allowed text-gray-300"
              }`}
            >
              {t.label}
              {!t.enabled && <span className="ml-1 text-[9px]">SOON</span>}
            </button>
          ))}
        </nav>

        {/* Feed body */}
        <div className="flex flex-col gap-4 px-2">
          {loading && <FeedSkeleton />}

          {!loading && error && (
            <div className="rounded-2xl bg-red-50 p-4 text-center">
              <p className="text-sm font-bold text-red-700">{error}</p>
              <button
                type="button"
                onClick={() => setActiveTab(activeTab)} // re-trigger via state
                className="mt-2 text-xs font-extrabold text-red-600 underline"
              >
                Coba lagi
              </button>
            </div>
          )}

          {!loading && !error && posts.length === 0 && (
            <EmptyTabState tab={activeTab} />
          )}

          {posts.map((post) => (
            <FeedVideoCard
              key={post.id}
              post={post}
              onOpenComments={setCommentPostId}
            />
          ))}

          {/* Sentinel untuk infinite scroll */}
          {hasMore && !loading && (
            <div ref={sentinelRef} className="h-8" aria-hidden="true">
              {loadingMore && (
                <p className="text-center text-xs font-bold text-gray-400">Memuat...</p>
              )}
            </div>
          )}
        </div>
      </div>

      <FeedCommentSheet
        open={commentSheetOpen}
        postId={commentPostId}
        onClose={() => setCommentPostId(null)}
      />
    </FeedActiveVideoProvider>
  );
}

function FeedSkeleton() {
  return (
    <>
      {[0, 1].map((i) => (
        <div
          key={i}
          className="overflow-hidden rounded-3xl border border-gray-100 bg-white"
        >
          <div className="flex items-center gap-2 px-4 py-3">
            <div className="h-9 w-9 animate-pulse rounded-full bg-gray-200" />
            <div className="h-3 w-32 animate-pulse rounded-full bg-gray-200" />
          </div>
          <div className="mx-4 aspect-[9/16] animate-pulse rounded-2xl bg-gray-200" />
          <div className="space-y-2 p-4">
            <div className="h-3 w-3/4 animate-pulse rounded-full bg-gray-200" />
            <div className="h-3 w-1/2 animate-pulse rounded-full bg-gray-200" />
          </div>
        </div>
      ))}
    </>
  );
}

function EmptyTabState({ tab }: { tab: FeedPostTab }) {
  const messages: Record<FeedPostTab, { title: string; subtitle: string }> = {
    REKOMENDASI: {
      title: "Belum ada konten",
      subtitle: "Konten rekomendasi akan muncul di sini. Cek lagi nanti!",
    },
    PROMO: {
      title: "Belum ada promo",
      subtitle: "Promo terbaru dari Natalo akan muncul di sini.",
    },
    KOMUNITAS: {
      title: "Komunitas akan segera hadir",
      subtitle: "Fitur upload video komunitas sedang disiapkan.",
    },
  };
  const m = messages[tab];
  return (
    <div className="rounded-3xl border border-dashed border-gray-200 bg-white p-8 text-center">
      <p className="text-sm font-extrabold text-gray-700">{m.title}</p>
      <p className="mt-1 text-xs text-gray-500">{m.subtitle}</p>
    </div>
  );
}
