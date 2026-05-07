"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";

export type HomeBanner = {
  id: string;
  title: string;
  subtitle: string;
  emoji: string;
  bgFrom: string;
  bgTo: string;
  href: string;
};

type Props = {
  banners: HomeBanner[];
  intervalMs?: number;
};

export function BannerCarousel({ banners, intervalMs = 4000 }: Props) {
  const [active, setActive] = useState(0);
  const trackRef = useRef<HTMLDivElement>(null);
  const pausedRef = useRef(false);

  useEffect(() => {
    if (banners.length <= 1) return;
    const id = setInterval(() => {
      if (pausedRef.current) return;
      setActive((prev) => (prev + 1) % banners.length);
    }, intervalMs);
    return () => clearInterval(id);
  }, [banners.length, intervalMs]);

  useEffect(() => {
    const track = trackRef.current;
    if (!track) return;
    const child = track.children[active] as HTMLElement | undefined;
    if (!child) return;
    track.scrollTo({ left: child.offsetLeft - 16, behavior: "smooth" });
  }, [active]);

  function handleScroll() {
    const track = trackRef.current;
    if (!track) return;
    const childWidth = (track.children[0] as HTMLElement | undefined)?.offsetWidth ?? 1;
    const idx = Math.round(track.scrollLeft / childWidth);
    if (idx !== active && idx >= 0 && idx < banners.length) setActive(idx);
  }

  return (
    <div
      onPointerDown={() => (pausedRef.current = true)}
      onPointerUp={() => {
        pausedRef.current = false;
      }}
      onPointerLeave={() => {
        pausedRef.current = false;
      }}
    >
      <div
        ref={trackRef}
        onScroll={handleScroll}
        className="flex snap-x snap-mandatory gap-3 overflow-x-auto scroll-smooth px-4 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      >
        {banners.map((b) => (
          <Link
            key={b.id}
            href={b.href}
            className="relative h-[200px] w-[88%] shrink-0 snap-center overflow-hidden rounded-2xl shadow-sm active:opacity-90"
            style={{
              background: `linear-gradient(135deg, ${b.bgFrom}, ${b.bgTo})`,
            }}
          >
            <div className="flex h-full flex-col justify-between p-5 text-white">
              <div>
                <p className="text-xs font-bold uppercase tracking-wider opacity-90">
                  {b.subtitle}
                </p>
                <h3 className="mt-1 text-xl font-black leading-tight">{b.title}</h3>
              </div>
              <div className="flex items-end justify-between">
                <span className="rounded-full bg-white/20 px-3 py-1 text-xs font-bold backdrop-blur-sm">
                  Lihat &rarr;
                </span>
                <span className="text-5xl drop-shadow-lg">{b.emoji}</span>
              </div>
            </div>
          </Link>
        ))}
      </div>

      <div className="mt-3 flex justify-center gap-1.5">
        {banners.map((_, i) => (
          <button
            key={i}
            onClick={() => setActive(i)}
            aria-label={`Slide ${i + 1}`}
            className={`h-1.5 rounded-full transition-all ${
              i === active ? "w-6 bg-orange-500" : "w-1.5 bg-zinc-300"
            }`}
          />
        ))}
      </div>
    </div>
  );
}
