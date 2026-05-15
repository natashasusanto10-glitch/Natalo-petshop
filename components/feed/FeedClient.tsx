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
  type ReactNode,
} from "react";
import { FiHeart, FiMessageCircle, FiPlus, FiSend } from "react-icons/fi";
import type { FeedListResponse, FeedPostListItem } from "@/lib/feed/types";
import { FeedActiveVideoProvider, useFeedActiveVideo } from "./FeedActiveVideoContext";
import { FeedVideoCard } from "./FeedVideoCard";
import { FeedPostPlaceholder } from "./FeedPostPlaceholder";
import { FeedCommentSheet } from "./FeedCommentSheet";
import { FeedCreatePostSheet } from "./FeedCreatePostSheet";
import { getVirtualWindow } from "@/lib/feed/runtime-config";

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
          className="absolute right-5 top-[calc(env(safe-area-inset-top)+14px)] z-30 grid h-11 w-11 place-items-center text-white transition active:scale-95"
        >
          <FiPlus className="h-9 w-9" />
        </button>

        <div
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
          {showEmpty && <FeedComingSoonActionRail />}

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
      <FeedCreatePostSheet
        open={createPostOpen}
        onClose={() => setCreatePostOpen(false)}
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
    <div className="box-border flex h-full items-center justify-center px-6 [padding-bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+2rem)] [padding-top:calc(env(safe-area-inset-top)+1rem)]">
      <div className="flex max-w-[min(78vw,320px)] flex-col items-center text-center">
        <FeedComingSoonIllustration />
        <h1 className="mt-6 text-[34px] font-semibold leading-tight tracking-normal text-white">
          Natalo Feed
        </h1>
        <p className="mt-2 text-[21px] font-medium leading-tight tracking-normal text-white/90">
          Coming Soon
        </p>
      </div>
    </div>
  );
}

function FeedComingSoonActionRail() {
  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute right-7 z-20 flex flex-col items-center gap-9 text-white [bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom)+8.75rem)]"
    >
      <ComingSoonAction icon={<FiHeart className="h-9 w-9" strokeWidth={2.35} />} count="1.2K" />
      <ComingSoonAction
        icon={<FiMessageCircle className="h-9 w-9" strokeWidth={2.35} />}
        count="128"
      />
      <ComingSoonAction icon={<FiSend className="h-9 w-9" strokeWidth={2.35} />} />
    </div>
  );
}

function ComingSoonAction({ icon, count }: { icon: ReactNode; count?: string }) {
  return (
    <div className="flex flex-col items-center justify-center">
      {icon}
      {count && <span className="mt-1.5 text-sm font-medium leading-none text-white">{count}</span>}
    </div>
  );
}

function FeedComingSoonIllustration() {
  return (
    <svg
      viewBox="0 0 320 300"
      role="img"
      aria-label="Ilustrasi kucing dan anjing Natalo Petshop"
      className="h-auto w-[min(70vw,280px)] max-w-full drop-shadow-[0_18px_36px_rgba(30,95,191,0.20)]"
    >
      <defs>
        <linearGradient id="feedBagBlue" x1="0" x2="1" y1="0" y2="1">
          <stop offset="0" stopColor="#2F8CFF" />
          <stop offset="1" stopColor="#1452B7" />
        </linearGradient>
        <linearGradient id="feedBlob" x1="0" x2="1" y1="0" y2="1">
          <stop offset="0" stopColor="#132331" />
          <stop offset="1" stopColor="#071016" />
        </linearGradient>
      </defs>

      <path
        d="M57 180c-31-50 13-100 64-112 50-12 68-47 113-21 48 28 69 100 39 147-31 49-93 66-144 58-38-6-57-25-72-72Z"
        fill="url(#feedBlob)"
        opacity="0.92"
      />

      <g fill="#2F8CFF">
        <path d="M35 117c9-9 18-7 20 2 2 10-11 17-20 25-9-8-22-15-20-25 2-9 11-11 20-2Z" />
        <path d="M281 125c6-6 13-4 14 2 1 7-8 12-14 18-7-6-16-11-14-18 1-6 8-8 14-2Z" opacity="0.9" />
        <path d="M259 72l5 10 10 5-10 5-5 10-5-10-10-5 10-5 5-10Z" />
        <path d="M285 81l3 6 6 3-6 3-3 6-3-6-6-3 6-3 3-6Z" opacity="0.8" />
        <path d="M75 133l4 8 8 4-8 4-4 8-4-8-8-4 8-4 4-8Z" />
      </g>
      <g fill="#FFFFFF" opacity="0.65">
        <circle cx="99" cy="57" r="8" />
        <circle cx="117" cy="52" r="7" />
        <circle cx="134" cy="60" r="7" />
        <circle cx="107" cy="75" r="7" />
        <path d="M112 64c10-5 25 6 25 18 0 8-8 12-18 8-9 4-18 0-18-8 0-8 4-14 11-18Z" />
      </g>

      <g transform="translate(56 169)">
        <path d="M13 13h53l-6 66H5L0 13h13Z" fill="url(#feedBagBlue)" />
        <path d="M16 20V8c0-7 7-13 17-13s17 6 17 13v12" fill="none" stroke="#E8F2FF" strokeWidth="4" strokeLinecap="round" />
        <circle cx="26" cy="48" r="5" fill="#fff" />
        <circle cx="39" cy="48" r="5" fill="#fff" />
        <circle cx="32.5" cy="39" r="5" fill="#fff" />
        <path d="M21 59c5-9 18-9 23 0 2 5-2 9-7 7-3-1-6-1-9 0-6 2-10-3-7-7Z" fill="#fff" />
        <text x="33" y="81" textAnchor="middle" fill="#fff" fontSize="13" fontWeight="800" fontFamily="Arial, sans-serif">
          NATALO
        </text>
      </g>

      <g transform="translate(108 102)">
        <path d="M19 55c-8-32 8-58 33-58s41 26 33 58l-9 64H28l-9-64Z" fill="#F6F7F9" />
        <path d="M17 28 4 1c24 4 36 16 38 37L17 28ZM87 28 100 1C76 5 64 17 62 38l25-10Z" fill="#F6F7F9" />
        <path d="m23 30-8-16 17 12-9 4ZM81 30l8-16-17 12 9 4Z" fill="#F1C2BE" />
        <path d="M20 54c0 48 20 76 32 76s32-28 32-76c-14 10-49 10-64 0Z" fill="#D6D8DA" />
        <circle cx="38" cy="52" r="4" fill="#101010" />
        <circle cx="66" cy="52" r="4" fill="#101010" />
        <path d="M47 63c5 4 8 4 11 0" fill="none" stroke="#101010" strokeWidth="3" strokeLinecap="round" />
        <path d="M52 68c-5 10-18 9-25 1M52 68c5 10 18 9 25 1" fill="none" stroke="#101010" strokeWidth="3" strokeLinecap="round" />
        <path d="M18 116h68" stroke="#252525" strokeWidth="4" strokeLinecap="round" opacity="0.18" />
        <path d="M31 88h42v15c-10 9-32 9-42 0V88Z" fill="#1E5FBF" />
        <circle cx="52" cy="102" r="13" fill="#2F8CFF" />
        <text x="52" y="107" textAnchor="middle" fill="#fff" fontSize="16" fontWeight="800" fontFamily="Arial, sans-serif">
          N
        </text>
      </g>

      <g transform="translate(177 75)">
        <path d="M19 76C15 30 42 4 77 13c35 9 52 46 44 88l-8 55H30L19 76Z" fill="#F3C37F" />
        <path d="M28 45C5 38 2 74 16 103c14 1 27-22 12-58ZM113 45c23-7 26 29 12 58-14 1-27-22-12-58Z" fill="#F1B66E" />
        <circle cx="58" cy="71" r="5" fill="#111" />
        <circle cx="88" cy="71" r="5" fill="#111" />
        <path d="M68 84c5 4 12 4 17 0" fill="none" stroke="#111" strokeWidth="4" strokeLinecap="round" />
        <path d="M75 85c-4 8-17 9-25 2M75 85c4 8 17 9 25 2" fill="none" stroke="#111" strokeWidth="3" strokeLinecap="round" />
        <path d="M68 101c4 16 22 16 26 0" fill="#FF8B8B" />
        <path d="M33 111h83l-42 34-41-34Z" fill="#1E5FBF" />
        <text x="74" y="133" textAnchor="middle" fill="#fff" fontSize="24" fontWeight="800" fontFamily="Arial, sans-serif">
          N
        </text>
        <path d="M117 155c24-10 23-37 7-48" fill="none" stroke="#F3C37F" strokeWidth="13" strokeLinecap="round" />
      </g>

      <g transform="translate(241 210)">
        <ellipse cx="35" cy="22" rx="34" ry="17" fill="#0D45AD" />
        <ellipse cx="35" cy="17" rx="31" ry="13" fill="#2F8CFF" />
        <ellipse cx="35" cy="17" rx="20" ry="7" fill="#071016" opacity="0.95" />
        <circle cx="26" cy="30" r="4" fill="#fff" />
        <circle cx="38" cy="30" r="4" fill="#fff" />
        <circle cx="32" cy="23" r="4" fill="#fff" />
        <path d="M22 40c5-9 18-9 23 0 2 5-2 8-7 6-4-1-8-1-11 0-5 2-8-2-5-6Z" fill="#fff" />
      </g>
    </svg>
  );
}
