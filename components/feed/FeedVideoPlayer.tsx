"use client";

/**
 * Video player untuk satu feed item dgn:
 * - Thumbnail-first paint (poster attribute) sebelum video load
 * - IntersectionObserver → register sebagai "active" kalau viewport ≥60%
 * - Single autoplay: hanya yg activeId === myId yang play
 * - Pause + unload source saat keluar viewport jauh (memory hygiene)
 * - Tap-to-toggle play/pause untuk manual control
 *
 * Spec 10.1, 10.2, 10.3, 10.4 — semua di sini.
 */
import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import { useFeedActiveVideo } from "./FeedActiveVideoContext";

type Props = {
  postId: string;
  videoUrl: string;
  thumbnailUrl: string | null;
  durationSec: number | null;
  aspectRatio?: number; // width/height ratio; default 9/16 (portrait)
};

export function FeedVideoPlayer({
  postId,
  videoUrl,
  thumbnailUrl,
  durationSec,
  aspectRatio = 9 / 16,
}: Props) {
  const { activeId, setActiveId, paused } = useFeedActiveVideo();
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [hasInteracted, setHasInteracted] = useState(false);
  // `loadSrc`: set true saat dekat viewport. Belum set src ke <video>
  // berarti zero network/memory cost. Spec 10.3 (lazy load).
  const [loadSrc, setLoadSrc] = useState(false);
  // Track visibility ratio supaya bisa decide unload kalau jauh dari viewport.
  const [farFromViewport, setFarFromViewport] = useState(false);

  const isActive = activeId === postId && !paused;

  // Observer 1: ≥60% visible → register sebagai active
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const obs = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting && entry.intersectionRatio >= 0.6) {
            setActiveId(postId);
          }
        }
      },
      { threshold: [0.6] },
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, [postId, setActiveId]);

  // Observer 2: ≥10% visible → load src (preload metadata). Jauh dari
  // viewport → unload src untuk hemat memory.
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
            // Sudah keluar viewport > 50% — kalau jauh, schedule unload.
            setFarFromViewport(true);
          }
        }
      },
      { rootMargin: "200% 0px 200% 0px", threshold: [0, 0.1] },
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, []);

  // Play/pause sesuai isActive + paused flag global.
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    if (isActive && hasInteracted) {
      // play() bisa reject di iOS kalau tidak ada user gesture chain.
      // Catch supaya tidak unhandled — fallback: tap manual.
      v.play().catch(() => {});
    } else {
      v.pause();
    }
  }, [isActive, hasInteracted]);

  // First user tap di mana saja di page = enable autoplay (browser policy).
  // Setelah tap pertama, autoplay diizinkan tanpa gesture.
  useEffect(() => {
    function onFirstInteraction() {
      setHasInteracted(true);
      window.removeEventListener("touchstart", onFirstInteraction);
      window.removeEventListener("click", onFirstInteraction);
    }
    window.addEventListener("touchstart", onFirstInteraction, { once: true });
    window.addEventListener("click", onFirstInteraction, { once: true });
    return () => {
      window.removeEventListener("touchstart", onFirstInteraction);
      window.removeEventListener("click", onFirstInteraction);
    };
  }, []);

  function togglePlay() {
    const v = videoRef.current;
    if (!v) return;
    setHasInteracted(true);
    if (v.paused) {
      setActiveId(postId);
      v.play().catch(() => {});
    } else {
      v.pause();
    }
  }

  return (
    <div
      ref={containerRef}
      className="relative w-full overflow-hidden rounded-2xl bg-black"
      style={{ aspectRatio: `${aspectRatio}` }}
      onClick={togglePlay}
    >
      {/* Thumbnail layer — selalu render, hide saat video sudah playing.
          Image priority=false supaya tidak boost LCP di scroll. */}
      {thumbnailUrl && (
        <Image
          src={thumbnailUrl}
          alt=""
          fill
          sizes="(max-width: 768px) 100vw, 480px"
          className="object-cover"
          style={{ opacity: isActive ? 0 : 1, transition: "opacity 200ms" }}
        />
      )}

      {/* Video element — src hanya di-set saat dekat viewport, di-clear saat jauh. */}
      <video
        ref={videoRef}
        src={loadSrc && !farFromViewport ? videoUrl : undefined}
        poster={thumbnailUrl ?? undefined}
        playsInline
        muted={false}
        loop
        preload={loadSrc && !farFromViewport ? "metadata" : "none"}
        className="absolute inset-0 h-full w-full object-cover"
        // Hide kalau belum aktif — pakai thumbnail layer di atas.
        style={{ opacity: isActive ? 1 : 0 }}
      />

      {/* Play badge overlay saat tidak aktif */}
      {!isActive && (
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
          <div className="rounded-full bg-black/40 p-3 backdrop-blur-sm">
            <svg viewBox="0 0 24 24" className="h-8 w-8 fill-white">
              <path d="M8 5v14l11-7z" />
            </svg>
          </div>
        </div>
      )}

      {/* Duration label bottom-right */}
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
