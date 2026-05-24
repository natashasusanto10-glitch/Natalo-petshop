"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useFeedActiveVideo } from "./FeedActiveVideoContext";
import {
  getPreloadTier,
  getRecommendedVideoQuality,
  useNetworkTier,
  type NetworkTier,
  type VideoQuality,
} from "@/lib/feed/runtime-config";
import { useVideoMetrics } from "./useVideoMetrics";
import {
  bunnyHlsToMp4,
  bunnyMp4ToHls,
  rewriteBunnyMp4Quality,
} from "@/lib/feed/bunny";
import { FEED_PLAYBACK_TEARDOWN_EVENT } from "@/lib/feed/teardown";
import { BlurhashCanvas } from "./BlurhashCanvas";

function isHlsUrl(url: string | null | undefined): boolean {
  if (!url) return false;
  return url.includes(".m3u8");
}

/**
 * Pick the best playback URL for this post, network-aware:
 *
 *   WiFi (stable, high bandwidth)    → HLS playlist (adaptive bitrate,
 *                                      player switch quality mid-clip)
 *   4G / cellular-fast / unknown     → MP4 progressive di quality sesuai
 *                                      (single-file CDN cache, no manifest
 *                                      overhead — better untuk clip ≤60s)
 *   3G / cellular-slow / save-data   → MP4 progressive di low quality
 *                                      (240/360/480p, hindari HLS overhead)
 *   Offline                          → return as-is, biar player error
 *                                      handler tangani fallback
 *
 * Rasional: HLS unggul untuk video panjang dengan kondisi network yang
 * berubah. Untuk feed ≤60s di network stabil, MP4 progressive lebih cepat
 * start play (1 file fetch, no manifest parse) dan lebih cache-friendly.
 * Cuma WiFi tier yang dapat HLS karena di sana adaptive bitrate worth
 * the overhead.
 */
function resolvePlaybackUrl(
  url: string,
  quality: VideoQuality,
  tier: NetworkTier,
): string {
  const wantsHls = tier === "wifi";

  if (isHlsUrl(url)) {
    // Stored as HLS (legacy atau future webhook change). Kalau network
    // slow, rewrite ke MP4 di quality yang aman. Lainnya pakai HLS.
    if (tier === "cellular-slow") {
      return bunnyHlsToMp4(url, quality) ?? url;
    }
    return url;
  }

  // Stored MP4 (current webhook default). Upgrade ke HLS untuk WiFi
  // supaya adaptive bitrate aktif. Sisanya rewrite quality MP4.
  if (wantsHls) {
    return bunnyMp4ToHls(url) ?? rewriteBunnyMp4Quality(url, quality) ?? url;
  }
  return rewriteBunnyMp4Quality(url, quality) ?? url;
}

type Props = {
  postId: string;
  /** Position in the parent feed list. Threaded down so we can derive
   *  distance-from-active for preload tier decisions. */
  index: number;
  videoUrl: string;
  thumbnailUrl: string | null;
  /** Blurhash LQIP — render sebagai canvas placeholder paling belakang
   *  supaya user tidak pernah lihat bg-black tembus walaupun thumbnail
   *  network masih loading. Null untuk legacy post yang belum di-backfill. */
  thumbnailBlurhash?: string | null;
  durationSec: number | null;
  aspectRatio?: number;
  className?: string;
  /** Called when user double-taps on the video. Parent (FeedVideoCard) owns
   *  the like state and decides what to do (Instagram pattern: only ever
   *  SETS liked=true, never unlikes — repeated double-taps just replay the
   *  heart animation). */
  onDoubleTap?: () => void;
};

// Window for detecting double-tap. 300ms standard Instagram pattern;
// shorter feels too strict, longer makes single-tap feel laggy.
const DOUBLE_TAP_WINDOW_MS = 300;

// Showing a spinner shorter than this would flash on every swipe even when
// playback is effectively instant.
const LOADING_INDICATOR_DELAY_MS = 1200;

// Start the "swap to next slot" sequence this long before the natural end.
// Browser play() on the prepared slot at currentTime=0 takes ~50-150ms to
// produce its first frame; SWAP_LEAD_TIME_SEC gives that window so the
// crossfade has content on both sides.
const SWAP_LEAD_TIME_SEC = 0.25;

// After a swap, the previous slot stays mounted at the active position for
// this long (in case the new slot's play() rejects and we need to fall
// back). Then it's rewound + paused so it's ready for the NEXT swap cycle.
const SWAP_CLEANUP_MS = 400;

type Slot = "A" | "B";

export function FeedVideoPlayer({
  postId,
  index,
  videoUrl,
  thumbnailUrl,
  thumbnailBlurhash,
  durationSec,
  aspectRatio = 9 / 16,
  className = "",
  onDoubleTap,
}: Props) {
  const { activeId, activeIndex, setActive, paused, soundOn, toggleSound } =
    useFeedActiveVideo();
  const videoARef = useRef<HTMLVideoElement>(null);
  const videoBRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  // 2-video swap state: A or B is currently the "front" (visible + playing).
  // The other is paused at currentTime=0, ready to swap in at end-of-loop.
  // Approach inspired by Instagram Reels — avoids the WKWebView seek-clear
  // black flash that pre-seek mid-frame still showed.
  const [activeSlot, setActiveSlot] = useState<Slot>("A");
  // src is attached to both video elements from first paint for the active
  // card (index 0). Cards further away wait for IntersectionObserver before
  // attaching — saves memory + bandwidth on long feeds.
  const [loadSrc, setLoadSrc] = useState(index === 0);
  const [farFromViewport, setFarFromViewport] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [showLoadingIndicator, setShowLoadingIndicator] = useState(false);
  const [playbackProgress, setPlaybackProgress] = useState(0);

  // Network-aware video quality: re-render saat user pindah jaringan
  // (mis. WiFi → 4G) supaya URL playback ikut ganti quality. Initial value
  // dipilih saat mount; useNetworkTier subscribe ke connection.change.
  const networkTier = useNetworkTier();
  const videoQuality = useMemo<VideoQuality>(
    () => {
      // Re-evaluate quality berdasarkan tier sekarang. networkTier sebagai
      // dependency triggering re-compute saat user pindah jaringan.
      void networkTier;
      return getRecommendedVideoQuality();
    },
    [networkTier],
  );
  // Pilih playback URL berdasarkan network tier + quality. WiFi dapat HLS
  // adaptive, mobile dapat MP4 progressive di quality network-appropriate.
  // Re-derive saat user pindah jaringan (mis. WiFi → 4G) supaya stream
  // ganti dari HLS ke MP4 720p tanpa wait next post.
  const playbackUrl = useMemo(
    () => resolvePlaybackUrl(videoUrl, videoQuality, networkTier),
    [videoUrl, videoQuality, networkTier],
  );
  const isHls = isHlsUrl(playbackUrl);

  // Aspect ratio classification — tentukan rendering mode:
  //   - portrait 9:16 (default Reels) → object-cover, fill viewport
  //   - non-portrait (landscape/square/odd ratios) → object-contain di tengah
  //     + blurred thumbnail background fill viewport (Instagram pattern)
  // Threshold 0.05 toleransi untuk video ~9:16 yang sedikit off (mis. iPhone
  // 9:19.5 ratio 0.462 vs ideal 9:16 = 0.5625).
  const isPortrait = useMemo(() => {
    // aspectRatio passed in dari FeedVideoCard sebagai width/height
    // (mis. 9/16 = 0.5625 untuk portrait, 16/9 = 1.78 untuk landscape).
    return aspectRatio <= 0.65;
  }, [aspectRatio]);

  // Treat card di index 0 sebagai active sampai IntersectionObserver fire
  // setActive untuk card lain. Tanpa ini, first render punya isActive=false
  // → autoPlay=false → video element mount tanpa autoplay attribute → iOS
  // tidak trigger playback otomatis.
  const isFallbackActiveForFirstCard = activeId === null && index === 0;
  const isActive = (activeId === postId || isFallbackActiveForFirstCard) && !paused;
  // Distance from the currently-active card. Unknown active → treat as far.
  const distance =
    activeIndex == null ? Infinity : Math.abs(index - activeIndex);
  // Network-aware tier: WiFi gets aggressive prefetch, cellular-slow holds back.
  const preloadMode = getPreloadTier(distance);

  // Pre-decode poster thumbnail untuk card adjacent (distance ≤ 1) supaya
  // saat user scroll ke sini, gambar sudah ter-decode di compositor cache.
  // Tanpa ini, `decoding="sync"` di <img> bawah masih decode at paint
  // time saat card snap masuk viewport — bisa block paint 5-20ms di iOS
  // → terlihat sebagai black flash. img.decode() shift decode work ke
  // background sebelum user perlu lihat gambarnya.
  useEffect(() => {
    if (!thumbnailUrl) return;
    if (distance > 1) return;
    let cancelled = false;
    const img = new Image();
    img.src = thumbnailUrl;
    void img.decode().catch(() => {
      // decode() bisa reject untuk image yang corrupted / CORS — safe ignore,
      // visible <img> tag akan tetap coba decode sync di paint time.
      if (cancelled) return;
    });
    return () => {
      cancelled = true;
    };
  }, [thumbnailUrl, distance]);

  // Helper: refs accessor by slot.
  const getRef = useCallback(
    (slot: Slot): HTMLVideoElement | null =>
      slot === "A" ? videoARef.current : videoBRef.current,
    [],
  );

  const updatePlaybackProgress = useCallback(() => {
    const video = getRef(activeSlot);
    if (!video) return;
    const duration =
      Number.isFinite(video.duration) && video.duration > 0
        ? video.duration
        : durationSec ?? 0;
    if (!duration || duration <= 0) {
      setPlaybackProgress(0);
      return;
    }
    const nextProgress = Math.min(
      Math.max(video.currentTime / duration, 0),
      1,
    );
    setPlaybackProgress((current) =>
      Math.abs(current - nextProgress) > 0.002 ? nextProgress : current,
    );
  }, [activeSlot, durationSec, getRef]);

  // Telemetry — collects canPlay / firstFrame / buffer counts. Hook only
  // accepts one ref; pass the currently-active slot so metrics track the
  // visible playback.
  const metricsRef = useRef<HTMLVideoElement>(
    null,
  ) as React.MutableRefObject<HTMLVideoElement | null>;
  useEffect(() => {
    metricsRef.current = getRef(activeSlot);
  }, [activeSlot, getRef]);
  useVideoMetrics({
    videoRef: metricsRef as React.RefObject<HTMLVideoElement | null>,
    postId,
    isActive,
    videoDurationSec: durationSec,
  });

  // Teardown — pause + drop src on both slots when route leaves /feed so iOS
  // doesn't keep the AVPlayer alive in the background.
  useEffect(() => {
    function onTeardown() {
      setShowLoadingIndicator(false);
      setIsPlaying(false);
      setPlaybackProgress(0);
      setLoadSrc(false);
      setFarFromViewport(true);
      for (const slot of ["A", "B"] as const) {
        const v = getRef(slot);
        if (!v) continue;
        try {
          v.pause();
          v.removeAttribute("autoplay");
          v.removeAttribute("src");
          v.preload = "none";
          v.load();
        } catch {
          // Media teardown is best-effort and must not block route changes.
        }
      }
    }
    window.addEventListener(FEED_PLAYBACK_TEARDOWN_EVENT, onTeardown);
    return () => window.removeEventListener(FEED_PLAYBACK_TEARDOWN_EVENT, onTeardown);
  }, [getRef]);

  // HLS fallback path. New Bunny posts ship as MP4 progressive (much better
  // cache behaviour for short feed clips). Only legacy posts that we cannot
  // rewrite (e.g. external HLS providers in the future) hit this path: Safari
  // plays HLS natively, other browsers fall back to hls.js. Note: HLS attach
  // only to slot A — HLS legacy content doesn't benefit from 2-video swap
  // (it's old, low-priority for smoothness).
  useEffect(() => {
    const video = videoARef.current;
    if (!video) return;
    if (!loadSrc || farFromViewport) return;
    if (!isHlsUrl(playbackUrl)) return;
    if (video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = playbackUrl;
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
        startLevel: -1,
        capLevelToPlayerSize: true,
      });
      hls.loadSource(playbackUrl);
      hls.attachMedia(video);
      hlsInstance = hls;
    });
    return () => {
      destroyed = true;
      hlsInstance?.destroy();
    };
  }, [playbackUrl, loadSrc, farFromViewport]);

  // IO observer: track when this card becomes the ≥60% visible one.
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

  // Far-from-viewport guard — drop src + preload="none" for cards way off
  // screen to free memory. 300% rootMargin means ±1 cards stay loaded so
  // swipe is instant.
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
      { rootMargin: "300% 0px 300% 0px", threshold: [0, 0.1] },
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, []);

  // Play active slot, pause inactive slot, ensure inactive is rewound to 0.
  // Runs whenever isActive, activeSlot, or soundOn change.
  useEffect(() => {
    const activeV = getRef(activeSlot);
    const inactiveV = getRef(activeSlot === "A" ? "B" : "A");
    if (!activeV) return;

    // Inactive slot: always muted (cegah audio leak ke video lain) + paused
    // + rewound. Ready to swap in.
    if (inactiveV) {
      inactiveV.muted = true;
      if (!inactiveV.paused) {
        try {
          inactiveV.pause();
        } catch {}
      }
      if (inactiveV.currentTime > 0.05) {
        try {
          inactiveV.currentTime = 0;
        } catch {}
      }
    }

    // Active slot follows soundOn (user choice).
    activeV.muted = !isActive || !soundOn;

    if (!isActive) {
      try {
        activeV.pause();
      } catch {}
      setIsPlaying(false);
      return;
    }

    let cancelled = false;
    const tryPlay = () => {
      if (cancelled) return;
      // Re-assert muted before play() — defensive.
      activeV.muted = !soundOn;
      const p = activeV.play();
      if (p && typeof p.then === "function") {
        p.catch(() => {
          // Silent — iOS rejects first play() when buffer not ready. Event
          // listeners retry.
        });
      }
    };
    tryPlay();
    // Retry on multiple events because iOS WKWebView fires loadedmetadata
    // before canplay sometimes, and other browsers vice versa.
    activeV.addEventListener("loadedmetadata", tryPlay);
    activeV.addEventListener("canplay", tryPlay);
    activeV.addEventListener("loadeddata", tryPlay);
    activeV.addEventListener("canplaythrough", tryPlay);
    return () => {
      cancelled = true;
      activeV.removeEventListener("loadedmetadata", tryPlay);
      activeV.removeEventListener("canplay", tryPlay);
      activeV.removeEventListener("loadeddata", tryPlay);
      activeV.removeEventListener("canplaythrough", tryPlay);
    };
  }, [isActive, activeSlot, soundOn, getRef]);

  // Spinner: show only when active card stays genuinely UN-buffered for
  // >LOADING_INDICATOR_DELAY_MS. Source of truth = video.readyState saja
  // (HAVE_FUTURE_DATA = 3 atau lebih = bisa play forward).
  //
  // PENTING: jangan include `video.paused` di cek ini — user pause
  // intentional (tap untuk pause) tetap punya readyState 4 (HAVE_ENOUGH_
  // DATA), tapi paused=true. Kalau ikut paused, spinner muncul setelah
  // 1.2s saat user pause normal — bug yang user laporkan.
  //
  // Tampilkan spinner cuma kalau buffering beneran (data belum cukup):
  //   readyState 0 (NOTHING) / 1 (METADATA) / 2 (CURRENT_DATA) → stalled
  //   readyState 3 (FUTURE_DATA) / 4 (ENOUGH_DATA) → ready, no spinner
  useEffect(() => {
    if (!isActive) {
      setShowLoadingIndicator(false);
      return;
    }
    const t = window.setTimeout(() => {
      const video = getRef(activeSlot);
      if (!video) {
        setShowLoadingIndicator(true);
        return;
      }
      const hasEnoughData = video.readyState >= 3;
      setShowLoadingIndicator(!hasEnoughData);
    }, LOADING_INDICATOR_DELAY_MS);
    return () => window.clearTimeout(t);
  }, [isActive, isPlaying, activeSlot, getRef]);

  useEffect(() => {
    setPlaybackProgress(0);
  }, [postId, videoUrl]);

  // Lightweight running progress for the active Feed video. Event updates
  // handle pause/buffer/metadata changes, while RAF makes the bar feel smooth
  // during playback without touching inactive cards.
  useEffect(() => {
    const active = getRef(activeSlot);
    if (!active || !isActive) return;
    let frame: number | null = null;
    let cancelled = false;

    const stopLoop = () => {
      if (frame !== null) {
        window.cancelAnimationFrame(frame);
        frame = null;
      }
    };

    const tick = () => {
      if (cancelled) return;
      updatePlaybackProgress();
      if (!active.paused && !active.ended) {
        frame = window.requestAnimationFrame(tick);
      } else {
        frame = null;
      }
    };

    const startLoop = () => {
      if (frame !== null) return;
      frame = window.requestAnimationFrame(tick);
    };

    const stopAtCurrentPosition = () => {
      stopLoop();
      updatePlaybackProgress();
    };

    const handleEnded = () => {
      stopLoop();
      setPlaybackProgress(1);
    };

    active.addEventListener("loadedmetadata", updatePlaybackProgress);
    active.addEventListener("durationchange", updatePlaybackProgress);
    active.addEventListener("timeupdate", updatePlaybackProgress);
    active.addEventListener("seeked", updatePlaybackProgress);
    active.addEventListener("play", startLoop);
    active.addEventListener("playing", startLoop);
    active.addEventListener("pause", stopAtCurrentPosition);
    active.addEventListener("waiting", stopAtCurrentPosition);
    active.addEventListener("ended", handleEnded);

    updatePlaybackProgress();
    if (!active.paused && !active.ended) startLoop();

    return () => {
      cancelled = true;
      stopLoop();
      active.removeEventListener("loadedmetadata", updatePlaybackProgress);
      active.removeEventListener("durationchange", updatePlaybackProgress);
      active.removeEventListener("timeupdate", updatePlaybackProgress);
      active.removeEventListener("seeked", updatePlaybackProgress);
      active.removeEventListener("play", startLoop);
      active.removeEventListener("playing", startLoop);
      active.removeEventListener("pause", stopAtCurrentPosition);
      active.removeEventListener("waiting", stopAtCurrentPosition);
      active.removeEventListener("ended", handleEnded);
    };
  }, [activeSlot, getRef, isActive, updatePlaybackProgress]);

  // 2-video swap: timeupdate on active slot watches for end-of-clip, kicks
  // off play() on the other slot, swaps active. This avoids HTML5 video's
  // seek-to-0 which clears WKWebView's paint buffer (the "black flash").
  useEffect(() => {
    const active = getRef(activeSlot);
    const next = getRef(activeSlot === "A" ? "B" : "A");
    if (!active || !next) return;
    let swapping = false;
    let lastTime = active.currentTime;

    function onTimeUpdate() {
      const v = active;
      if (!v || !next) return;
      if (
        !swapping &&
        v.duration &&
        Number.isFinite(v.duration) &&
        v.duration > 0.5 &&
        v.duration - v.currentTime < SWAP_LEAD_TIME_SEC
      ) {
        swapping = true;
        // Prep + play the next slot starting from 0. Its src has been
        // preloaded since mount (same playbackUrl as active slot, browser
        // cache hit → no extra network round-trip).
        try {
          if (next.currentTime > 0.05) next.currentTime = 0;
        } catch {}
        next.muted = !soundOn;
        const p = next.play();
        if (p && typeof p.then === "function") {
          p.catch(() => {
            // play() rejected on the prep slot — likely buffer not ready.
            // Don't swap; let the OLD slot keep playing past natural end
            // and the `ended` fallback below handles loop the old way.
            swapping = false;
          });
        }
        // Swap active slot immediately so render shows next slot's element
        // on top. Old slot fades out via opacity, but it KEEPS playing
        // (audibly silent because muted will flip true below). The browser
        // crossfades smoothly because both slots are decoding & painting.
        setPlaybackProgress(1);
        setActiveSlot((cur) => (cur === "A" ? "B" : "A"));
        window.requestAnimationFrame(() => setPlaybackProgress(0));
        // After SWAP_CLEANUP_MS, pause + rewind the old slot so it's ready
        // for NEXT loop. By then the crossfade is done.
        window.setTimeout(() => {
          try {
            active.pause();
            active.currentTime = 0;
            active.muted = true;
          } catch {}
        }, SWAP_CLEANUP_MS);
        return;
      }
      if (v.currentTime !== lastTime) {
        lastTime = v.currentTime;
        setIsPlaying(true);
        setShowLoadingIndicator(false);
      }
    }

    function onPlaying() {
      setIsPlaying(true);
      setShowLoadingIndicator(false);
    }

    function onEnded() {
      // Safety net: if timeupdate's SWAP_LEAD_TIME_SEC window was missed
      // (rare — timeupdate fires ~4x/s in iOS), fall back to the simple
      // loop on the SAME slot. Yes this might flash black, but it's
      // strictly better than the video stopping.
      const v = active;
      if (!v) return;
      try {
        setPlaybackProgress(1);
        v.currentTime = 0;
        window.requestAnimationFrame(() => setPlaybackProgress(0));
        v.play().catch(() => {});
      } catch {}
    }

    active.addEventListener("timeupdate", onTimeUpdate);
    active.addEventListener("playing", onPlaying);
    active.addEventListener("ended", onEnded);
    return () => {
      active.removeEventListener("timeupdate", onTimeUpdate);
      active.removeEventListener("playing", onPlaying);
      active.removeEventListener("ended", onEnded);
    };
  }, [activeSlot, soundOn, getRef]);

  // Tap detection: single-tap toggles play/pause, double-tap fires like
  // callback + heart animation. Single-tap action is DELAYED by
  // DOUBLE_TAP_WINDOW_MS so we can cancel it if a second tap arrives in
  // that window (Instagram pattern).
  const lastTapTimeRef = useRef(0);
  const singleTapTimerRef = useRef<number | null>(null);
  const heartAnimIdRef = useRef(0);
  const [activeHeartId, setActiveHeartId] = useState<number | null>(null);

  function togglePlay() {
    const active = getRef(activeSlot);
    if (!active) return;
    if (active.paused) {
      setActive(postId, index);
      active.play().catch(() => setIsPlaying(false));
    } else {
      try {
        active.pause();
      } catch {}
    }
  }

  function handleSurfaceClick() {
    const now = Date.now();
    if (now - lastTapTimeRef.current < DOUBLE_TAP_WINDOW_MS) {
      // Double-tap detected — cancel pending single-tap action.
      if (singleTapTimerRef.current) {
        window.clearTimeout(singleTapTimerRef.current);
        singleTapTimerRef.current = null;
      }
      lastTapTimeRef.current = 0;
      // Spawn heart animation (unique id supaya React force re-mount kalau
      // user double-tap berkali-kali cepat — animation restart, tidak skip).
      heartAnimIdRef.current += 1;
      const animId = heartAnimIdRef.current;
      setActiveHeartId(animId);
      window.setTimeout(() => {
        setActiveHeartId((current) => (current === animId ? null : current));
      }, 850);
      onDoubleTap?.();
      return;
    }
    lastTapTimeRef.current = now;
    // Delay togglePlay supaya kita bisa cancel kalau double-tap kedua datang.
    if (singleTapTimerRef.current) {
      window.clearTimeout(singleTapTimerRef.current);
    }
    singleTapTimerRef.current = window.setTimeout(() => {
      togglePlay();
      singleTapTimerRef.current = null;
    }, DOUBLE_TAP_WINDOW_MS);
  }

  // Cleanup timer on unmount.
  useEffect(() => {
    return () => {
      if (singleTapTimerRef.current) {
        window.clearTimeout(singleTapTimerRef.current);
      }
    };
  }, []);

  // src attached to BOTH video elements when within preload range. Same URL
  // → browser shares the underlying byte cache; no double-download.
  const attachSrc = loadSrc && !farFromViewport && !isHls;
  const elementSrc = attachSrc ? playbackUrl : undefined;
  // Slot A handles HLS via the dedicated effect above. Slot B always uses
  // MP4 direct src (HLS legacy content gets simple loop, not seamless).
  const slotBSrc = attachSrc ? playbackUrl : undefined;
  const showSoundToggle = isActive && !isPlaying && !showLoadingIndicator;

  // Video object-fit decision:
  //   - Portrait 9:16 → cover (fill viewport, edge-to-edge Reels feel)
  //   - Non-portrait (landscape 16:9, square 1:1, dll) → contain
  //     (no crop, center video + show blur background di sisi kosong)
  const videoObjectFit = isPortrait ? "object-cover" : "object-contain";

  return (
    <div
      ref={containerRef}
      data-feed-video-player
      className={`relative w-full overflow-hidden bg-black ${className}`}
      style={{ aspectRatio: `${aspectRatio}` }}
      onClick={handleSurfaceClick}
    >
      {/* Layer 0: Blurhash LQIP placeholder — di-decode instan dari ~30
          byte hash, render ke canvas 32x32 yang CSS scale-up jadi blur
          smooth. Visible saat thumbnail real masih loading dari Bunny CDN.
          Saat thumbnailUrl <img> ter-load, dia render on top dan cover
          blurhash. Saat video first frame painted, video element cover
          poster. 3 layer stacking yang gradual ke tajam. */}
      {thumbnailBlurhash && (
        <BlurhashCanvas
          hash={thumbnailBlurhash}
          className={`absolute inset-0 h-full w-full ${videoObjectFit}`}
        />
      )}

      {/* Background: pure black via `bg-black` class. Untuk non-portrait
          video, bars muncul dari object-contain di atas/bawah (landscape)
          atau kiri/kanan (square) — bars-nya pure black, 1 warna dengan
          Feed page yang gelap, lebih clean daripada blur backdrop. */}
      {thumbnailUrl && (
        <img
          src={thumbnailUrl}
          alt=""
          loading="eager"
          fetchPriority="high"
          // decoding="sync" — force iOS decode + paint poster sebelum
          // composite frame berikutnya. Default "async" boleh skip paint
          // saat WKWebView sibuk scroll-snap layer reflow → user lihat
          // bg-black tembus dari container. Sync lebih mahal di main
          // thread (image decode block) tapi worth it untuk poster
          // tunggal ~50-200 KB.
          decoding="sync"
          className={`absolute inset-0 h-full w-full ${videoObjectFit}`}
          onError={(event) => {
            event.currentTarget.style.display = "none";
          }}
          // Poster ALWAYS visible — letakkan di paling belakang sebagai
          // "safety net" supaya kalau video element belum punya frame
          // (decode lag, scroll-snap composite, dll), user lihat poster
          // tidak bg-black. Video on top akan cover poster saat ready.
          // Sebelumnya pakai isPlaying gate + opacity 0/1 — bikin flicker
          // saat scroll antar card karena ada window mana poster sudah
          // hilang tapi video belum siap.
          style={{ opacity: 1 }}
        />
      )}

      {/* Slot A — primary video element. Receives HLS via hls.js when
          applicable. */}
      <video
        ref={videoARef}
        data-feed-video
        data-slot="A"
        src={isHls ? undefined : elementSrc}
        poster={thumbnailUrl ?? undefined}
        playsInline
        muted
        autoPlay={isActive && activeSlot === "A"}
        preload={attachSrc ? preloadMode : "none"}
        className={`absolute inset-0 h-full w-full ${videoObjectFit}`}
        onPlay={() => setIsPlaying(true)}
        onPause={() => {
          // Only mark not-playing if THIS is the front slot AND we're not
          // mid-swap (where back slot might be the new front).
          if (activeSlot === "A") setIsPlaying(false);
        }}
        // Opacity gated by activeSlot saja (TANPA isPlaying gate). Reasoning:
        // - Slot active selalu opacity 1, browser native pakai `poster`
        //   attribute (= thumbnailUrl) sebagai placeholder sampai first
        //   frame decode. Plus ada <img> overlay behind sebagai safety
        //   net tambahan. User tidak pernah lihat bg-black tembus karena
        //   ada 2 layer poster (native + img) dan video on top.
        // - Transition 150ms always-on. Initial mount sudah opacity 1
        //   (tidak transition dari 0), jadi tidak ada "fade from black"
        //   di card pertama kali aktif. Yang trigger transition cuma
        //   loop swap (activeSlot A↔B) — exactly what we want.
        style={{
          opacity: activeSlot === "A" ? 1 : 0,
          transition: "opacity 150ms ease-out",
        }}
      />

      {/* Slot B — secondary video element. Mounted alongside slot A for the
          seamless loop swap. Same src → browser shares cache. */}
      <video
        ref={videoBRef}
        data-feed-video
        data-slot="B"
        src={slotBSrc}
        poster={thumbnailUrl ?? undefined}
        playsInline
        muted
        autoPlay={isActive && activeSlot === "B"}
        preload={attachSrc ? preloadMode : "none"}
        className={`absolute inset-0 h-full w-full ${videoObjectFit}`}
        onPlay={() => setIsPlaying(true)}
        onPause={() => {
          if (activeSlot === "B") setIsPlaying(false);
        }}
        style={{
          opacity: activeSlot === "B" ? 1 : 0,
          transition: "opacity 150ms ease-out",
        }}
      />

      {/* Loading indicator — only after the configurable delay. */}
      {showLoadingIndicator && (
        <div
          data-feed-loading-overlay
          className="pointer-events-none absolute inset-0 flex items-center justify-center"
        >
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

      {/* Double-tap heart animation. Big pink heart pops di tengah video
          dengan scale + fade out. Key by animId supaya re-mount tiap
          double-tap baru (animation restart, tidak nge-skip). */}
      {activeHeartId !== null && (
        <div
          key={activeHeartId}
          className="pointer-events-none absolute inset-0 z-[2] flex items-center justify-center"
          aria-hidden="true"
        >
          <svg
            viewBox="0 0 24 24"
            className="h-32 w-32 drop-shadow-[0_8px_24px_rgba(255,48,64,0.55)]"
            style={{
              fill: "#FF3040",
              animation: "natalo-feed-heart-pop 850ms cubic-bezier(0.22, 1, 0.36, 1) forwards",
            }}
          >
            <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z" />
          </svg>
          <style>{`
            @keyframes natalo-feed-heart-pop {
              0% {
                transform: scale(0.2) rotate(-10deg);
                opacity: 0;
              }
              22% {
                transform: scale(1.18) rotate(0deg);
                opacity: 1;
              }
              45% {
                transform: scale(1) rotate(0deg);
                opacity: 1;
              }
              100% {
                transform: scale(1.5) rotate(8deg);
                opacity: 0;
              }
            }
          `}</style>
        </div>
      )}

      <VideoProgressBar progress={playbackProgress} />

      {/* Cinema mode — Wave 4 #6 scoped down version.
          Tap untuk masuk fullscreen native player.
          iOS: pakai webkitEnterFullscreen() → AVPlayerViewController muncul
            dengan kontrol native (AirPlay, PIP, scrubbing, picture-in-picture).
          Android: pakai standard Fullscreen API.
          Web: same Fullscreen API, browser-native player UI.

          Gate dengan `showSoundToggle` (= isActive && !isPlaying &&
          !showLoadingIndicator) — sama dengan sound toggle. Tujuannya:
          tombol hanya muncul saat user pause video, supaya tidak distract
          saat user lagi nonton. */}
      {showSoundToggle && (
        <button
          type="button"
          aria-label="Cinema mode — buka di player native"
          onClick={(e) => {
            e.stopPropagation();
            const video = getRef(activeSlot);
            if (!video) return;
            // iOS-specific API yang trigger AVPlayerViewController native
            // (better UX dibanding standard Fullscreen API yang cuma
            // fullscreen WebView). Cek availability dulu — non-Safari /
            // non-iOS fallback ke standard requestFullscreen.
            const v = video as HTMLVideoElement & {
              webkitEnterFullscreen?: () => void;
            };
            if (typeof v.webkitEnterFullscreen === "function") {
              try {
                v.webkitEnterFullscreen();
                return;
              } catch {
                // Continue to fallback
              }
            }
            // Fallback: standard Fullscreen API (Android / desktop)
            if (typeof video.requestFullscreen === "function") {
              video.requestFullscreen().catch(() => {
                // Fullscreen rejected — likely permission. Silent fail.
              });
            }
          }}
          className="absolute right-3 z-[3] grid h-10 w-10 place-items-center rounded-full bg-black/40 text-white shadow-[0_8px_20px_rgba(0,0,0,0.28)] backdrop-blur-md transition active:scale-95"
          // Cinema button selalu di-stack di bawah sound toggle saat
          // visible — keduanya share gate showSoundToggle, jadi cinema
          // selalu render bersama sound. Position 132px = sound (76px)
          // + sound button height (40px) + gap (16px).
          style={{
            top: "calc(env(safe-area-inset-top, 0px) + 132px)",
          }}
        >
          <svg
            viewBox="0 0 24 24"
            className="h-5 w-5 fill-white"
            aria-hidden
          >
            <path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z" />
          </svg>
        </button>
      )}

      {/* Sound toggle — hanya muncul saat video pause supaya feed tetap clean
          ketika playback berjalan. */}
      {showSoundToggle && (
        <button
          type="button"
          aria-label={soundOn ? "Matikan suara" : "Nyalakan suara"}
          onClick={(e) => {
            e.stopPropagation();
            toggleSound();
          }}
          className="absolute right-3 z-[3] grid h-10 w-10 place-items-center rounded-full bg-black/40 text-white shadow-[0_8px_20px_rgba(0,0,0,0.28)] backdrop-blur-md transition active:scale-95"
          style={{ top: "calc(env(safe-area-inset-top, 0px) + 76px)" }}
        >
          {soundOn ? (
            <svg viewBox="0 0 24 24" className="h-6 w-6 fill-white" aria-hidden>
              <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3a4.5 4.5 0 0 0-2.5-4.03v8.05A4.5 4.5 0 0 0 16.5 12zM14 3.23v2.06A7.01 7.01 0 0 1 19 12a7 7 0 0 1-5 6.71v2.06A9 9 0 0 0 21 12a9 9 0 0 0-7-8.77z" />
            </svg>
          ) : (
            <svg viewBox="0 0 24 24" className="h-6 w-6 fill-white" aria-hidden>
              <path d="M16.5 12a4.5 4.5 0 0 0-2.5-4.03v2.21l2.45 2.45c.03-.21.05-.42.05-.63zm2.5 0a6.97 6.97 0 0 1-1.06 3.7l1.52 1.52A8.99 8.99 0 0 0 21 12c0-4.28-3-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3 3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.51-1.42.93-2.25 1.18v2.06a8.99 8.99 0 0 0 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4 9.91 6.09 12 8.18V4z" />
            </svg>
          )}
        </button>
      )}
    </div>
  );
}

function VideoProgressBar({ progress }: { progress: number }) {
  const safeProgress = Math.min(Math.max(progress, 0), 1);
  return (
    <div
      className="pointer-events-none absolute inset-x-0 bottom-0 z-[4] flex h-5 items-end"
      aria-hidden="true"
    >
      <div className="h-[2px] w-full bg-white/20">
        <div
          className="h-full origin-left bg-white/90"
          style={{ transform: `scaleX(${safeProgress})` }}
        />
      </div>
    </div>
  );
}
