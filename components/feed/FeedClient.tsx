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
  const sentinelRef = useRef<HTMLDivElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  useFeedChrome();

  // iOS Capacitor WKWebView ships with
  // `mediaTypesRequiringUserActionForPlayback = .all`, which blocks the
  // initial muted autoplay until the user has touched anything inside the
  // web view. The native side gets fixed by FeedAutoplayViewController
  // (Swift override) but that needs a TestFlight rebuild to take effect.
  // Meanwhile: on the very first touch anywhere inside the scroll
  // container, kick off play() on every visible video so the user only
  // ever has to tap once (and that tap can be a swipe — touchstart fires
  // before the gesture is interpreted as scroll, so even swipes count).
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    let armed = true;
    const handler = () => {
      if (!armed) return;
      armed = false;
      el.querySelectorAll("video").forEach((video) => {
        if (video.paused && video.muted) {
          video.play().catch(() => {});
        }
      });
    };
    el.addEventListener("touchstart", handler, { passive: true, once: true });
    el.addEventListener("pointerdown", handler, { passive: true, once: true });
    return () => {
      el.removeEventListener("touchstart", handler);
      el.removeEventListener("pointerdown", handler);
    };
  }, []);

  // CSS scroll-snap-mandatory is supposed to force snapping, but iOS
  // Capacitor's WKWebView occasionally lets a flick rest mid-way between
  // two cards (Apple's snap engine treats `scroll-snap-stop: always` as a
  // hint, not a hard contract, in some build versions). Add a JS fallback:
  // 150ms after the scroll stops, if the scroll position isn't a multiple
  // of the card height, snap it programmatically. Belt-and-suspenders for
  // the TikTok-style hard-paged feel.
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    let timer: number | null = null;
    function snapNow() {
      const container = el;
      if (!container) return;
      const cellHeight = container.clientHeight;
      if (!cellHeight) return;
      const current = container.scrollTop;
      const nearest = Math.round(current / cellHeight) * cellHeight;
      if (Math.abs(current - nearest) > 1) {
        container.scrollTo({ top: nearest, behavior: "smooth" });
      }
    }
    function onScroll() {
      if (timer != null) window.clearTimeout(timer);
      timer = window.setTimeout(snapNow, 150);
    }
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      el.removeEventListener("scroll", onScroll);
      if (timer != null) window.clearTimeout(timer);
    };
  }, []);

  // Pull-to-refresh wiring: PullToRefresh in the root layout dispatches
  // "app-refresh" after the user pulls past the threshold. Bump reloadKey
  // so the existing fetch effect re-runs from the top.
  useEffect(() => {
    const handler = () => setReloadKey((k) => k + 1);
    window.addEventListener("app-refresh", handler);
    return () => window.removeEventListener("app-refresh", handler);
  }, []);

  useEffect(() => {
    router.prefetch("/feed/upload");
  }, [router]);

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
    void hapticTap();
    router.push("/feed/upload");
  }

  return (
    <FeedActiveVideoProvider>
      <div className="relative mx-auto flex h-full max-w-2xl flex-col">
        <button
          type="button"
          onClick={startUploadFlow}
          aria-label="Buat postingan"
          className="absolute right-[22px] top-[calc(env(safe-area-inset-top)+18px)] z-30 grid h-8 w-8 place-items-center text-white drop-shadow-[0_2px_8px_rgba(0,0,0,0.5)] transition active:scale-95"
        >
          <FiPlus className="h-8 w-8" />
        </button>

        <div
          ref={scrollRef}
          // data-no-pull → PullToRefresh in the root layout sees this and
          // bows out instead of stealing vertical touch gestures from the
          // feed's snap-scroller. Keeps swipe-up-for-next-video instant.
          //
          // Critical for TikTok-style hard-paged feed: NO padding-bottom
          // here even though the bottom nav sits below. The nav uses
          // position: fixed and overlays the video card edge-to-edge; if
          // we add padding the scroll content shifts up and the snap cells
          // are no longer exactly one viewport tall, letting the next card
          // peek through. The action buttons / caption / product pill
          // inside the card already account for the nav height with their
          // own bottom offsets so they stay visible above the overlay.
          data-no-pull
          className="min-h-0 flex-1 snap-y snap-mandatory overflow-y-auto overscroll-contain [-ms-overflow-style:none] [scrollbar-width:none] md:space-y-3 md:px-2 md:py-2 [&::-webkit-scrollbar]:hidden"
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
    </FeedActiveVideoProvider>
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
            // `snap-always` forces the scroll-snap engine to land on exactly
            // one card per scroll gesture. Without it iOS Safari can rest
            // mid-way between two cards on quick flicks, showing the bottom
            // half of video N and top half of video N+1 at the same time.
            // Combined with `snap-mandatory` on the parent it gives the
            // TikTok-style hard-paged feel: every release jumps to a single
            // full-screen video.
            className="snap-start snap-always"
            // Match the snap height of <FeedVideoCard>'s article so the
            // wrapper is a single snap cell and scroll position stays
            // consistent regardless of which child renders.
            //
            // Both `height: 100%` AND `minHeight: 100%` are required: the
            // article inside uses `min-h-full` which only resolves a
            // percentage when the parent has a *definite* `height` (per CSS
            // spec — a parent that only has `min-height` returns `auto` to
            // the child, which resolves to 0). Without the explicit height,
            // the article collapses to 0 px and the entire feed renders blank
            // even though React mounts the component tree correctly.
            style={{ height: "100%", minHeight: "100%" }}
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
