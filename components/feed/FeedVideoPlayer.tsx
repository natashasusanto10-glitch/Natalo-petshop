"use client";

import { useEffect, useRef, useState } from "react";
import { useFeedActiveVideo } from "./FeedActiveVideoContext";
import { getPreloadTier } from "@/lib/feed/runtime-config";
import { useVideoMetrics } from "./useVideoMetrics";

function isHlsUrl(url: string | null | undefined): boolean {
  if (!url) return false;
  return url.includes(".m3u8");
}

type Props = {
  postId: string;
  /** List position passed by parent feed so we can derive distance-from-active. */
  index: number;
  videoUrl: string;
  thumbnailUrl: string | null;
  durationSec: number | null;
  aspectRatio?: number;
  className?: string;
};

const LOADING_INDICATOR_DELAY_MS = 500;

export function FeedVideoPlayer({
  postId,
  index,
  videoUrl,
  thumbnailUrl,
  durationSec,
  aspectRatio = 9 / 16,
  className = "",
}: Props) {
  const { activeId, activeIndex, setActive, paused } = useFeedActiveVideo();
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [loadSrc, setLoadSrc] = useState(false);
  const [farFromViewport, setFarFromViewport] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [showLoadingIndicator, setShowLoadingIndicator] = useState(false);

  const isActive = activeId === postId && !paused;
  // Distance from the currently-active card. Unknown active → treat as far.
  const distance =
    activeIndex == null ? Infinity : Math.abs(index - activeIndex);
  // Network-aware tier: WiFi gets aggressive prefetch, cellular-slow holds back.
  const preloadMode = getPreloadTier(distance);

  // Telemetry — collects canPlay / firstFrame / buffer counts and flushes
  // to /api/feed/metrics when this card stops being active or unmounts.
  useVideoMetrics({ videoRef, postId, isActive, videoDurationSec: durationSec });

  // HLS playback. Bunny serves .m3u8 playlists with adaptive bitrate
  // variants. Safari (iOS + macOS) plays HLS natively via the standard
  // <video src> path so we do nothing there. Other browsers (Android
  // Chrome / desktop Chrome / Firefox) need hls.js to translate the
  // playlist into MediaSource Extensions chunks. Dynamic import keeps
  // the ~120KB hls.js bundle out of the initial page chunk.
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    if (!loadSrc || farFromViewport) return;
    if (!isHlsUrl(videoUrl)) return;
    // Safari has native HLS — just let `<video src>` handle it.
    if (video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = videoUrl;
      return;
    }
    let destroyed = false;
    let hlsInstance: import("hls.js").default | null = null;
    void import("hls.js").then(({ default: Hls }) => {
      if (destroyed) return;
      if (!Hls.isSupported()) return;
      const hls = new Hls({
        maxBufferLength: 10,
        maxMaxBufferLength: 30,
        // Match preload tier — current card downloads more aggressively.
        startLevel: -1,
        capLevelToPlayerSize: true,
      });
      hls.loadSource(videoUrl);
      hls.attachMedia(video);
      hlsInstance = hls;
    });
    return () => {
      destroyed = true;
      hlsInstance?.destroy();
    };
  }, [videoUrl, loadSrc, farFromViewport]);

  const isHls = isHlsUrl(videoUrl);

  // Track when the active card changes via IntersectionObserver. Pass both
  // id and index so context can compute neighbours for preload decisions.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const obs = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting && entry.intersectionRatio >= 0.6) {
            setActive(postId, index);
          }
        }
      },
      { threshold: [0.6] },
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, [postId, index, setActive]);

  // Far-from-viewport guard so we can drop the video src entirely when the
  // card is way off-screen — meaningful memory savings on long feeds.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const obs = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setLoadSrc(true);
            setFarFromViewport(false);
          } else {
            setFarFromViewport(true);
            setIsPlaying(false);
          }
        }
      },
      { rootMargin: "200% 0px 200% 0px", threshold: [0, 0.1] },
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, []);

  // Play / pause based on active state.
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    if (isActive) {
      video.play().catch(() => {
        setIsPlaying(false);
      });
    } else {
      video.pause();
      setIsPlaying(false);
    }
  }, [isActive]);

  // Delayed loading indicator. Only surface a spinner if the video stays
  // un-playable for >500ms while it's the active card; fast loads (cached,
  // pre-warmed) never flash a spinner — the user perceives instant playback.
  useEffect(() => {
    if (!isActive || isPlaying) {
      setShowLoadingIndicator(false);
      return;
    }
    const t = window.setTimeout(() => {
      setShowLoadingIndicator(true);
    }, LOADING_INDICATOR_DELAY_MS);
    return () => window.clearTimeout(t);
  }, [isActive, isPlaying]);

  function togglePlay() {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) {
      setActive(postId, index);
      video.play().catch(() => {
        setIsPlaying(false);
      });
    } else {
      video.pause();
    }
  }

  return (
    <div
      ref={containerRef}
      className={`relative w-full overflow-hidden bg-black ${className}`}
      style={{ aspectRatio: `${aspectRatio}` }}
      onClick={togglePlay}
    >
      {thumbnailUrl && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={thumbnailUrl}
          alt=""
          className="absolute inset-0 h-full w-full object-cover"
          onError={(event) => {
            event.currentTarget.style.display = "none";
          }}
          style={{ opacity: isPlaying ? 0 : 1, transition: "opacity 200ms" }}
        />
      )}

      <video
        ref={videoRef}
        // For HLS we let the effect above attach the source (Safari native
        // sets src direct, other browsers hand the stream to hls.js).
        // For progressive MP4 we use the native <video src> path.
        src={loadSrc && !farFromViewport && !isHls ? videoUrl : undefined}
        poster={thumbnailUrl ?? undefined}
        playsInline
        muted
        loop
        preload={loadSrc && !farFromViewport ? preloadMode : "none"}
        className="absolute inset-0 h-full w-full object-cover"
        onPlay={() => setIsPlaying(true)}
        onPause={() => setIsPlaying(false)}
        onWaiting={() => setIsPlaying(false)}
        style={{ opacity: isPlaying ? 1 : 0, transition: "opacity 200ms" }}
      />

      {/* Loading indicator only appears after the configurable delay — fast
          loads never flash, slow loads get a subtle spinner instead of a
          black hole. */}
      {showLoadingIndicator && (
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
          <span
            className="h-9 w-9 animate-spin rounded-full border-[3px] border-white/30 border-t-white/90"
            aria-hidden="true"
          />
        </div>
      )}

      {!isPlaying && !showLoadingIndicator && (
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
          <div className="rounded-full bg-black/40 p-3 backdrop-blur-sm">
            <svg viewBox="0 0 24 24" className="h-8 w-8 fill-white">
              <path d="M8 5v14l11-7z" />
            </svg>
          </div>
        </div>
      )}

      {durationSec != null && durationSec > 0 && (
        <div className="pointer-events-none absolute bottom-2 right-2 rounded-full bg-black/60 px-2 py-0.5 text-[11px] font-bold text-white">
          {formatDuration(durationSec)}
        </div>
      )}
    </div>
  );
}

function formatDuration(sec: number) {
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}
