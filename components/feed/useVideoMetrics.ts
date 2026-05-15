"use client";

/**
 * Track per-card playback metrics for the customer feed:
 *   - canPlayMs       — loadstart → canplay (DASH-equivalent "Time to ready")
 *   - firstFrameMs    — loadstart → first `playing` event (Time to first frame)
 *   - bufferEvents    — number of `waiting` (rebuffer) events
 *   - totalBufferMs   — cumulative time spent in rebuffer
 *   - watchMs         — cumulative real playback time (excludes pauses)
 *
 * Data is fire-and-forget POSTed to /api/feed/metrics when the active
 * card switches away OR on unmount, whichever comes first. The endpoint
 * just acknowledges + console.logs for now — wire it to an analytics
 * provider (Mixpanel / Amplitude / PostHog) at that boundary when
 * available.
 */

import { useEffect, useRef } from "react";
import { describeDeviceMemory, describeNetwork } from "@/lib/feed/runtime-config";

type Metrics = {
  postId: string;
  canPlayMs: number;
  firstFrameMs: number;
  bufferEvents: number;
  totalBufferMs: number;
  watchMs: number;
  videoDurationSec: number | null;
};

function sendMetrics(payload: Metrics) {
  // Console first so you can eyeball during dev / TestFlight even before
  // the endpoint or analytics provider is wired.
  if (process.env.NODE_ENV !== "production") {
    // eslint-disable-next-line no-console
    console.info("[feed-metrics]", payload);
  }
  try {
    const body = JSON.stringify({
      ...payload,
      network: describeNetwork(),
      deviceMemory: describeDeviceMemory(),
    });
    // navigator.sendBeacon is the right tool here — survives page unload
    // (e.g. user closes app) and doesn't block the main thread.
    if (typeof navigator !== "undefined" && typeof navigator.sendBeacon === "function") {
      const blob = new Blob([body], { type: "application/json" });
      navigator.sendBeacon("/api/feed/metrics", blob);
      return;
    }
    void fetch("/api/feed/metrics", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      keepalive: true,
    }).catch(() => {});
  } catch {
    // Telemetry must never break the player. Swallow.
  }
}

export function useVideoMetrics(params: {
  videoRef: React.RefObject<HTMLVideoElement | null>;
  postId: string;
  isActive: boolean;
  videoDurationSec: number | null;
}) {
  const { videoRef, postId, isActive, videoDurationSec } = params;
  const metricsRef = useRef<Metrics>({
    postId,
    canPlayMs: 0,
    firstFrameMs: 0,
    bufferEvents: 0,
    totalBufferMs: 0,
    watchMs: 0,
    videoDurationSec,
  });
  const loadStartRef = useRef<number>(0);
  const bufferStartRef = useRef<number>(0);
  const lastPlayingAtRef = useRef<number>(0);
  const sentRef = useRef(false);

  // Reset accumulators each time the active video swaps in / out.
  useEffect(() => {
    if (!isActive) return;
    sentRef.current = false;
    metricsRef.current = {
      postId,
      canPlayMs: 0,
      firstFrameMs: 0,
      bufferEvents: 0,
      totalBufferMs: 0,
      watchMs: 0,
      videoDurationSec,
    };
    loadStartRef.current = 0;
    bufferStartRef.current = 0;
    lastPlayingAtRef.current = 0;
  }, [isActive, postId, videoDurationSec]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video || !isActive) return;

    function flush() {
      if (sentRef.current) return;
      // Roll up any in-flight playing window.
      if (lastPlayingAtRef.current > 0) {
        metricsRef.current.watchMs += performance.now() - lastPlayingAtRef.current;
        lastPlayingAtRef.current = 0;
      }
      if (metricsRef.current.firstFrameMs > 0) {
        sentRef.current = true;
        sendMetrics(metricsRef.current);
      }
    }

    const onLoadStart = () => {
      loadStartRef.current = performance.now();
    };
    const onCanPlay = () => {
      if (loadStartRef.current > 0 && metricsRef.current.canPlayMs === 0) {
        metricsRef.current.canPlayMs = performance.now() - loadStartRef.current;
      }
    };
    const onPlaying = () => {
      const now = performance.now();
      if (loadStartRef.current > 0 && metricsRef.current.firstFrameMs === 0) {
        metricsRef.current.firstFrameMs = now - loadStartRef.current;
      }
      if (bufferStartRef.current > 0) {
        metricsRef.current.totalBufferMs += now - bufferStartRef.current;
        bufferStartRef.current = 0;
      }
      lastPlayingAtRef.current = now;
    };
    const onWaiting = () => {
      metricsRef.current.bufferEvents += 1;
      bufferStartRef.current = performance.now();
      // Bank the watch window so far.
      if (lastPlayingAtRef.current > 0) {
        metricsRef.current.watchMs += performance.now() - lastPlayingAtRef.current;
        lastPlayingAtRef.current = 0;
      }
    };
    const onPause = () => {
      if (lastPlayingAtRef.current > 0) {
        metricsRef.current.watchMs += performance.now() - lastPlayingAtRef.current;
        lastPlayingAtRef.current = 0;
      }
    };
    const onEnded = () => {
      onPause();
      flush();
    };

    video.addEventListener("loadstart", onLoadStart);
    video.addEventListener("canplay", onCanPlay);
    video.addEventListener("playing", onPlaying);
    video.addEventListener("waiting", onWaiting);
    video.addEventListener("pause", onPause);
    video.addEventListener("ended", onEnded);

    return () => {
      video.removeEventListener("loadstart", onLoadStart);
      video.removeEventListener("canplay", onCanPlay);
      video.removeEventListener("playing", onPlaying);
      video.removeEventListener("waiting", onWaiting);
      video.removeEventListener("pause", onPause);
      video.removeEventListener("ended", onEnded);
      // Flush on swap-away or unmount.
      flush();
    };
  }, [videoRef, isActive, postId]);
}
