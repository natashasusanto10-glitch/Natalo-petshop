"use client";

/**
 * TikTok-style public feed: a single mixed vertical stream.
 *
 * The DB still stores `tab` for admin organization and backward compatibility,
 * but the customer-facing app no longer exposes Rekomendasi/Promo/Komunitas
 * columns. All ACTIVE posts are mixed in one snap-scrolling feed.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { FiPlus } from "react-icons/fi";
import type { FeedListResponse, FeedPostListItem } from "@/lib/feed/types";
import { FeedActiveVideoProvider } from "./FeedActiveVideoContext";
import { FeedVideoCard } from "./FeedVideoCard";
import { FeedCommentSheet } from "./FeedCommentSheet";

export function FeedClient() {
  const [posts, setPosts] = useState<FeedPostListItem[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);
  const [commentPostId, setCommentPostId] = useState<string | null>(null);
  const sentinelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setPosts([]);
    setCursor(null);
    setError(null);

    fetch("/api/feed/posts")
      .then((res) => {
        if (!res.ok) throw new Error("Gagal memuat feed");
        return res.json() as Promise<FeedListResponse>;
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
  }, [reloadKey]);

  const loadMore = useCallback(async () => {
    if (!cursor || loadingMore || !hasMore) return;
    setLoadingMore(true);
    try {
      const res = await fetch(`/api/feed/posts?cursor=${cursor}`);
      if (!res.ok) throw new Error();
      const data: FeedListResponse = await res.json();
      setPosts((prev) => [...prev, ...data.items]);
      setCursor(data.nextCursor);
      setHasMore(Boolean(data.nextCursor));
    } catch {
      // The sentinel will try again when it re-enters the viewport.
    } finally {
      setLoadingMore(false);
    }
  }, [cursor, hasMore, loadingMore]);

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

  const commentSheetOpen = useMemo(() => commentPostId !== null, [commentPostId]);

  return (
    <FeedActiveVideoProvider>
      <div className="relative mx-auto flex h-full max-w-2xl flex-col">
        <Link
          href="/feed/upload"
          aria-label="Upload video komunitas"
          className="absolute right-4 top-[calc(env(safe-area-inset-top)+1rem)] z-30 grid h-11 w-11 place-items-center text-white drop-shadow-[0_2px_8px_rgba(0,0,0,0.55)] transition active:scale-95"
        >
          <FiPlus className="h-9 w-9" />
        </Link>

        <div className="min-h-0 flex-1 snap-y snap-mandatory overflow-y-auto overscroll-contain pb-[calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+0.75rem)] [-ms-overflow-style:none] [scrollbar-width:none] md:space-y-3 md:px-2 md:pb-4 md:pt-2 [&::-webkit-scrollbar]:hidden">
          {loading && <FeedSkeleton />}

          {!loading && error && (
            <div className="rounded-3xl bg-white p-6 text-center">
              <p className="text-sm font-bold text-red-700">{error}</p>
              <button
                type="button"
                onClick={() => setReloadKey((key) => key + 1)}
                className="mt-3 rounded-full bg-natalo-600 px-4 py-2 text-xs font-extrabold text-white"
              >
                Coba lagi
              </button>
            </div>
          )}

          {!loading && !error && posts.length === 0 && <EmptyFeedState />}

          {posts.map((post) => (
            <FeedVideoCard
              key={post.id}
              post={post}
              onOpenComments={setCommentPostId}
            />
          ))}

          {hasMore && !loading && (
            <div ref={sentinelRef} className="h-8 snap-start" aria-hidden="true">
              {loadingMore && (
                <p className="text-center text-xs font-bold text-white/60">
                  Memuat...
                </p>
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
          className="overflow-hidden rounded-[28px] border border-white/10 bg-white"
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

function EmptyFeedState() {
  return (
    <div className="rounded-3xl border border-dashed border-white/15 bg-white p-8 text-center">
      <p className="text-sm font-extrabold text-gray-700">Belum ada konten</p>
      <p className="mt-1 text-xs leading-relaxed text-gray-500">
        Video, promo, dan konten komunitas Natalo akan tampil di sini dalam satu
        feed.
      </p>
    </div>
  );
}
