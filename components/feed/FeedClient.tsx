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
import { useRouter } from "next/navigation";
import { FiPlus } from "react-icons/fi";
import type { FeedListResponse, FeedPostListItem } from "@/lib/feed/types";
import { FeedActiveVideoProvider, useFeedActiveVideo } from "./FeedActiveVideoContext";
import { FeedVideoCard } from "./FeedVideoCard";
import { FeedPostPlaceholder } from "./FeedPostPlaceholder";
import { FeedCommentSheet } from "./FeedCommentSheet";
import { getVirtualWindow } from "@/lib/feed/runtime-config";
import { hapticTap } from "@/lib/native/haptics";

const UPLOAD_ROUTE_TRANSITION_MS = 300;

export function FeedClient() {
  const router = useRouter();
  const [posts, setPosts] = useState<FeedPostListItem[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);
  const [commentPostId, setCommentPostId] = useState<string | null>(null);
  const [uploadTransitioning, setUploadTransitioning] = useState(false);
  const sentinelRef = useRef<HTMLDivElement>(null);
  const uploadRouteTimerRef = useRef<number | null>(null);
  useFeedChrome();

  // Pull-to-refresh wiring: PullToRefresh in the root layout dispatches
  // "app-refresh" after the user pulls past the threshold. Bump reloadKey
  // so the existing fetch effect re-runs from the top.
  useEffect(() => {
    const handler = () => setReloadKey((k) => k + 1);
    window.addEventListener("app-refresh", handler);
    return () => window.removeEventListener("app-refresh", handler);
  }, []);

  useEffect(() => {
    return () => {
      if (uploadRouteTimerRef.current) {
        window.clearTimeout(uploadRouteTimerRef.current);
      }
    };
  }, []);

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

  function startUploadFlow() {
    if (uploadTransitioning) return;
    void hapticTap();
    setUploadTransitioning(true);
    uploadRouteTimerRef.current = window.setTimeout(() => {
      router.push("/feed/upload");
    }, UPLOAD_ROUTE_TRANSITION_MS);
  }

  return (
    <FeedActiveVideoProvider>
      <div
        className={`relative mx-auto flex h-full max-w-2xl flex-col transition-[opacity,transform] duration-300 [transition-timing-function:cubic-bezier(0.22,1,0.36,1)] ${
          uploadTransitioning ? "-translate-x-7 opacity-70" : "translate-x-0 opacity-100"
        }`}
      >
        <FeedTopHeader />
        <button
          type="button"
          onClick={startUploadFlow}
          disabled={uploadTransitioning}
          aria-label="Buat postingan"
          className="absolute right-5 top-[calc(env(safe-area-inset-top)+14px)] z-30 grid h-11 w-11 place-items-center text-white transition active:scale-95"
        >
          <FiPlus className="h-9 w-9" />
        </button>

        <div
          // data-no-pull → PullToRefresh in the root layout sees this and
          // bows out instead of stealing vertical touch gestures from the
          // feed's snap-scroller. Keeps swipe-up-for-next-video instant.
          data-no-pull
          className={`min-h-0 flex-1 snap-y snap-mandatory overflow-y-auto overscroll-contain [-ms-overflow-style:none] [scrollbar-width:none] md:space-y-3 md:px-2 md:pb-4 md:pt-2 [&::-webkit-scrollbar]:hidden ${
            showEmpty
              ? "pb-0"
              : "pb-[calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+0.75rem)]"
          }`}
        >
          {loading && null}

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

          <FeedPostsList posts={posts} onOpenComments={setCommentPostId} />

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
      {uploadTransitioning && <FeedUploadRouteTransition />}
    </FeedActiveVideoProvider>
  );
}

function FeedUploadRouteTransition() {
  return (
    <div
      className="pointer-events-none fixed inset-0 z-[1900] bg-black/45 backdrop-blur-[1px] animate-in fade-in duration-300"
      aria-hidden="true"
    >
      <div className="ml-auto flex h-full w-[94vw] max-w-2xl translate-x-0 flex-col rounded-l-[28px] bg-[#050505] text-white shadow-[-24px_0_60px_rgba(0,0,0,0.5)] [animation:feed-upload-route-enter_300ms_cubic-bezier(0.22,1,0.36,1)_both]">
        <div className="grid h-[calc(56px+env(safe-area-inset-top))] shrink-0 grid-cols-[64px_1fr_64px] items-end px-2 pb-2 pt-[env(safe-area-inset-top)]">
          <span className="grid h-11 w-11 place-items-center rounded-full bg-white/10 text-white/85">
            ×
          </span>
          <span className="pb-3 text-center text-sm font-black">Pilih Video</span>
          <span />
        </div>
        <div className="px-5 pt-6">
          <h2 className="text-3xl font-black tracking-normal">Pilih Video</h2>
          <p className="mt-2 max-w-[260px] text-sm font-semibold leading-6 text-white/58">
            Pilih atau upload video untuk dibagikan ke Feed.
          </p>
          <div className="mt-7 space-y-3">
            <div className="h-[96px] rounded-3xl bg-white/10" />
            <div className="h-[96px] rounded-3xl bg-white/10" />
          </div>
        </div>
      </div>
      <style jsx>{`
        @keyframes feed-upload-route-enter {
          from {
            transform: translate3d(100%, 0, 0);
          }
          to {
            transform: translate3d(0, 0, 0);
          }
        }
      `}</style>
    </div>
  );
}

/**
 * Inner posts list. Must live inside <FeedActiveVideoProvider> so it can
 * read activeIndex from context and decide which post is close enough to
 * warrant the full <FeedVideoCard> mount.
 *
 * One shared IntersectionObserver tracks every wrapper (full card OR
 * placeholder) — that way activeIndex still updates correctly as the user
 * scrolls past placeholders, and the virtual window slides with them.
 */
function FeedPostsList({
  posts,
  onOpenComments,
}: {
  posts: FeedPostListItem[];
  onOpenComments: (postId: string) => void;
}) {
  const { activeIndex, setActive } = useFeedActiveVideo();
  const cardRefs = useRef<Map<number, HTMLElement | null>>(new Map());
  // Read once per mount — deviceMemory is constant for the session, no
  // point in re-evaluating on every render.
  const virtualWindow = useMemo(() => getVirtualWindow(), []);

  useEffect(() => {
    if (posts.length === 0) return;
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting && entry.intersectionRatio >= 0.6) {
            const indexAttr = entry.target.getAttribute("data-index");
            const id = entry.target.getAttribute("data-post-id");
            const idx = indexAttr !== null ? Number(indexAttr) : -1;
            if (idx >= 0 && id) setActive(id, idx);
          }
        }
      },
      { threshold: [0.6] },
    );
    cardRefs.current.forEach((el) => {
      if (el) observer.observe(el);
    });
    return () => observer.disconnect();
    // Re-attach when post count grows (pagination append) so new wrappers
    // join the observer batch.
  }, [posts.length, setActive]);

  function registerRef(index: number, el: HTMLElement | null) {
    if (el) cardRefs.current.set(index, el);
    else cardRefs.current.delete(index);
  }

  return (
    <>
      {posts.map((post, index) => {
        // Until the first IO fires, treat post 0 as the active card so the
        // initial visible viewport gets a full card mount (otherwise the
        // user sees the placeholder for half a second on cold load).
        const effectiveActive = activeIndex ?? 0;
        const distance = Math.abs(index - effectiveActive);
        const renderFull = distance <= virtualWindow;

        return (
          <div
            key={post.id}
            ref={(el) => registerRef(index, el)}
            data-index={index}
            data-post-id={post.id}
            className="snap-start"
            // Match the snap height of <FeedVideoCard>'s article so the
            // wrapper is a single snap cell and scroll position stays
            // consistent regardless of which child renders.
            style={{ minHeight: "100%" }}
          >
            {renderFull ? (
              <FeedVideoCard
                post={post}
                index={index}
                onOpenComments={onOpenComments}
              />
            ) : (
              <FeedPostPlaceholder thumbnailUrl={post.thumbnailUrl} />
            )}
          </div>
        );
      })}
    </>
  );
}

function FeedTopHeader() {
  return (
    <div className="pointer-events-none absolute left-5 top-[calc(env(safe-area-inset-top)+18px)] z-30 flex items-center gap-2.5 text-white">
      <span className="grid h-9 w-9 place-items-center rounded-full bg-natalo-600 text-base font-black leading-none shadow-[0_6px_18px_rgba(30,95,191,0.35)]">
        NL
      </span>
      <span className="text-[22px] font-extrabold leading-none tracking-normal drop-shadow-[0_2px_8px_rgba(0,0,0,0.5)]">
        Feed
      </span>
    </div>
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

function EmptyFeedState() {
  return (
    <div className="box-border flex h-full items-center justify-center px-7 [padding-bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+2rem)] [padding-top:calc(env(safe-area-inset-top)+4rem)]">
      <div className="max-w-[300px] text-center">
        <h1 className="text-[24px] font-bold leading-tight tracking-normal text-white">
          Segera Hadir
        </h1>
        <p className="mt-3 text-sm font-medium leading-relaxed text-white/62">
          Natalo Feed sedang disiapkan untuk video, tips, promo, dan komunitas pet lovers.
        </p>
      </div>
    </div>
  );
}
