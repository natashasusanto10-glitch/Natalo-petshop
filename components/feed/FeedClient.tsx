"use client";

/**
 * TikTok-style public feed: a single mixed vertical stream.
 *
 * The DB still stores `tab` for admin organization and backward compatibility,
 * but the customer-facing app no longer exposes Rekomendasi/Promo/Komunitas
 * columns. All ACTIVE posts are mixed in one snap-scrolling feed.
 */
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { FiPlus } from "react-icons/fi";
import type { FeedListResponse, FeedPostListItem } from "@/lib/feed/types";
import { FeedActiveVideoProvider } from "./FeedActiveVideoContext";
import { FeedVideoCard } from "./FeedVideoCard";
import { FeedCommentSheet } from "./FeedCommentSheet";
import { FeedCreatePostSheet } from "./FeedCreatePostSheet";

export function FeedClient() {
  const [posts, setPosts] = useState<FeedPostListItem[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);
  const [commentPostId, setCommentPostId] = useState<string | null>(null);
  const [createPostOpen, setCreatePostOpen] = useState(false);
  const sentinelRef = useRef<HTMLDivElement>(null);
  useFeedChrome();

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
  const showEmpty = !loading && !error && posts.length === 0;

  return (
    <FeedActiveVideoProvider>
      <div className="relative mx-auto flex h-full max-w-2xl flex-col">
        <button
          type="button"
          onClick={() => setCreatePostOpen(true)}
          aria-label="Buat postingan"
          className="absolute right-5 top-[calc(env(safe-area-inset-top)+14px)] z-30 grid h-[52px] w-[52px] place-items-center rounded-full border border-white/35 bg-black/25 text-white shadow-[0_10px_28px_rgba(0,0,0,0.28)] backdrop-blur-xl transition active:scale-95"
        >
          <FiPlus className="h-8 w-8" />
        </button>

        <div
          className={`min-h-0 flex-1 snap-y snap-mandatory overflow-y-auto overscroll-contain [-ms-overflow-style:none] [scrollbar-width:none] md:space-y-3 md:px-2 md:pb-4 md:pt-2 [&::-webkit-scrollbar]:hidden ${
            showEmpty
              ? "pb-0"
              : "pb-[calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+0.75rem)]"
          }`}
        >
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

          {showEmpty && <EmptyFeedState />}

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
      <FeedCreatePostSheet
        open={createPostOpen}
        onClose={() => setCreatePostOpen(false)}
      />
    </FeedActiveVideoProvider>
  );
}

function useFeedChrome() {
  useLayoutEffect(() => {
    const root = document.documentElement;
    const body = document.body;
    const previousRootFeedRoute = root.dataset.feedRoute;
    const previousBodyFeedRoute = body.dataset.feedRoute;
    const previousRootBackground = root.style.backgroundColor;
    const previousBodyBackground = body.style.backgroundColor;
    const previousRootOverscroll = root.style.overscrollBehavior;
    const previousBodyOverscroll = body.style.overscrollBehavior;

    root.dataset.feedRoute = "true";
    body.dataset.feedRoute = "true";
    root.style.backgroundColor = "#000000";
    body.style.backgroundColor = "#000000";
    root.style.overscrollBehavior = "none";
    body.style.overscrollBehavior = "none";

    let cancelled = false;

    async function applyNativeChrome() {
      try {
        const { StatusBar, Style } = await import("@capacitor/status-bar");
        if (cancelled) return;
        await StatusBar.setOverlaysWebView({ overlay: true });
        if (cancelled) return;
        await StatusBar.setBackgroundColor({ color: "#00000000" });
        if (cancelled) return;
        await StatusBar.setStyle({ style: Style.Dark });
      } catch {
        // Browser/PWA tanpa Capacitor: cukup pakai CSS route background.
      }
    }

    void applyNativeChrome();
    const raf = window.requestAnimationFrame(() => void applyNativeChrome());
    const timer = window.setTimeout(() => void applyNativeChrome(), 350);

    return () => {
      cancelled = true;
      window.cancelAnimationFrame(raf);
      window.clearTimeout(timer);

      if (previousRootFeedRoute === undefined) {
        delete root.dataset.feedRoute;
      } else {
        root.dataset.feedRoute = previousRootFeedRoute;
      }
      if (previousBodyFeedRoute === undefined) {
        delete body.dataset.feedRoute;
      } else {
        body.dataset.feedRoute = previousBodyFeedRoute;
      }
      root.style.backgroundColor = previousRootBackground;
      body.style.backgroundColor = previousBodyBackground;
      root.style.overscrollBehavior = previousRootOverscroll;
      body.style.overscrollBehavior = previousBodyOverscroll;

      (async () => {
        try {
          const { StatusBar, Style } = await import("@capacitor/status-bar");
          await StatusBar.setOverlaysWebView({ overlay: false });
          await StatusBar.setBackgroundColor({ color: "#ffffff" });
          await StatusBar.setStyle({ style: Style.Light });
        } catch {}
      })();
    };
  }, []);
}

function FeedSkeleton() {
  return (
    <>
      {[0, 1].map((i) => (
        <div
          key={i}
          className="relative min-h-full snap-start overflow-hidden bg-black"
        >
          <div className="absolute inset-0 animate-pulse bg-gradient-to-br from-white/14 via-white/7 to-white/3" />
          <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-black/35 via-black/0 to-black/82" />
          <div className="absolute bottom-[calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+2.25rem)] left-4 right-24 space-y-3">
            <div className="h-4 w-36 animate-pulse rounded-full bg-white/20" />
            <div className="h-3 w-52 animate-pulse rounded-full bg-white/16" />
            <div className="h-3 w-40 animate-pulse rounded-full bg-white/12" />
          </div>
          <div className="absolute bottom-[calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+2.25rem)] right-4 flex flex-col items-center gap-4">
            <div className="h-8 w-8 animate-pulse rounded-full bg-white/18" />
            <div className="h-8 w-8 animate-pulse rounded-full bg-white/14" />
            <div className="h-8 w-8 animate-pulse rounded-full bg-white/10" />
          </div>
        </div>
      ))}
    </>
  );
}

function EmptyFeedState() {
  return (
    <div className="box-border flex h-full items-center justify-center px-6 [padding-bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+1rem)] [padding-top:env(safe-area-inset-top)]">
      <p className="text-lg font-black tracking-normal text-white/90">Segera Hadir</p>
    </div>
  );
}
