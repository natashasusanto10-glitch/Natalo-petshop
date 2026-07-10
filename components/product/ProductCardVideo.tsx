"use client";

import Image from "next/image";
import { useEffect, useId, useRef, useState } from "react";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";
import { releasePlay, requestPlay, subscribeSlotFree } from "./video-autoplay-registry";

/**
 * Area media kartu produk saat ada video: foto cover sebagai dasar +
 * <video> bisu/loop yang autoplay HANYA saat kartu terlihat (visible-only)
 * dan mendapat slot dari registry konkurensi. Kalau video gagal / belum
 * siap / tak dapat slot → tetap tampil foto. Tak pernah kotak hitam.
 */
export function ProductCardVideo({
  mp4Url,
  poster,
  alt,
  className = "",
  priority,
  mediaClassName = "object-cover",
}: {
  mp4Url: string;
  poster: string | null;
  alt: string;
  className?: string;
  priority?: boolean;
  mediaClassName?: string;
}) {
  const id = useId();
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [canPlay, setCanPlay] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const wrap = wrapRef.current;
    const video = videoRef.current;
    if (!wrap || !video || failed) return;

    let inView = false;
    const tryPlay = () => {
      if (!inView) return;
      if (!requestPlay(id)) return;
      video.play().then(() => setCanPlay(true)).catch(() => releasePlay(id));
    };
    const stop = () => {
      video.pause();
      releasePlay(id);
      setCanPlay(false);
    };

    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          inView = e.isIntersecting && e.intersectionRatio >= 0.6;
          if (inView) tryPlay();
          else stop();
        }
      },
      { threshold: [0, 0.6] },
    );
    io.observe(wrap);
    // Kartu yang gagal dapat slot saat masuk viewport dicoba lagi begitu
    // kartu lain melepas slotnya (lihat comment di registry).
    const unsubscribe = subscribeSlotFree(() => tryPlay());
    return () => {
      io.disconnect();
      unsubscribe();
      stop();
    };
  }, [id, failed]);

  return (
    <div ref={wrapRef} className={`absolute inset-0 ${className}`}>
      {poster ? (
        <Image
          src={poster}
          alt={alt}
          fill
          priority={priority}
          placeholder="blur"
          blurDataURL={IMAGE_BLUR_GRAY}
          sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 25vw"
          className={mediaClassName}
        />
      ) : (
        <div className="flex h-full items-center justify-center text-5xl text-gray-300">🐾</div>
      )}
      {!failed && (
        <video
          ref={videoRef}
          src={mp4Url}
          muted
          loop
          playsInline
          preload="none"
          aria-hidden="true"
          onError={() => setFailed(true)}
          className={`absolute inset-0 h-full w-full ${mediaClassName} transition-opacity duration-300 ${
            canPlay ? "opacity-100" : "opacity-0"
          }`}
        />
      )}
      {!failed && (
        <span className="pointer-events-none absolute bottom-1.5 right-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-black/55 text-white">
          <svg viewBox="0 0 24 24" fill="currentColor" className="h-3 w-3" aria-hidden="true"><path d="M8 5v14l11-7z" /></svg>
        </span>
      )}
    </div>
  );
}
