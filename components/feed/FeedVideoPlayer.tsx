"use client";

import { useEffect, useRef, useState } from "react";
import { useFeedActiveVideo } from "./FeedActiveVideoContext";

type Props = {
  postId: string;
  videoUrl: string;
  thumbnailUrl: string | null;
  durationSec: number | null;
  aspectRatio?: number;
  className?: string;
};

export function FeedVideoPlayer({
  postId,
  videoUrl,
  thumbnailUrl,
  durationSec,
  aspectRatio = 9 / 16,
  className = "",
}: Props) {
  const { activeId, setActiveId, paused } = useFeedActiveVideo();
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [loadSrc, setLoadSrc] = useState(false);
  const [farFromViewport, setFarFromViewport] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);

  const isActive = activeId === postId && !paused;

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

  function togglePlay() {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) {
      setActiveId(postId);
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
        src={loadSrc && !farFromViewport ? videoUrl : undefined}
        poster={thumbnailUrl ?? undefined}
        playsInline
        muted
        loop
        preload={loadSrc && !farFromViewport ? "metadata" : "none"}
        className="absolute inset-0 h-full w-full object-cover"
        onPlay={() => setIsPlaying(true)}
        onPause={() => setIsPlaying(false)}
        onWaiting={() => setIsPlaying(false)}
        style={{ opacity: isPlaying ? 1 : 0 }}
      />

      {!isPlaying && (
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
