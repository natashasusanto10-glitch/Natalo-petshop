"use client";

import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { brandProductHref } from "@/lib/brand-catalog";

export type BrandChoiceItem = {
  id: string | number;
  name: string;
  slug: string;
  logo?: string | null;
  imageClass?: string;
};

type BrandChoiceSectionProps = {
  brands: BrandChoiceItem[];
};

function BrandLogo({ brand }: { brand: BrandChoiceItem }) {
  const [failed, setFailed] = useState(false);
  const imageClass = brand.imageClass ?? "max-h-[46px] max-w-[104px]";

  if (!brand.logo || failed) {
    return (
      <div className="flex h-full w-full items-center justify-center px-1 text-center">
        <span className="line-clamp-2 text-[12px] font-black uppercase leading-tight text-natalo-700">
          {brand.name.replace(/\s+/g, " ")}
        </span>
      </div>
    );
  }

  return (
    <Image
      src={brand.logo}
      alt={`Logo ${brand.name}`}
      width={120}
      height={64}
      sizes="33vw"
      className={`h-auto w-auto object-contain mix-blend-multiply ${imageClass}`}
      onError={() => setFailed(true)}
    />
  );
}

export function BrandChoiceSection({ brands }: BrandChoiceSectionProps) {
  const scrollerRef = useRef<HTMLDivElement | null>(null);
  const resumeTimerRef = useRef<number | null>(null);
  const currentPageRef = useRef(0);
  const [autoPaused, setAutoPaused] = useState(false);
  const pageCount = useMemo(() => Math.max(1, Math.ceil(brands.length / 3)), [brands.length]);

  const pauseAutoSlide = useCallback(() => {
    setAutoPaused(true);
    if (resumeTimerRef.current) window.clearTimeout(resumeTimerRef.current);
    resumeTimerRef.current = window.setTimeout(() => {
      setAutoPaused(false);
    }, 5500);
  }, []);

  // Auto-slide: advance to next page every 4s. Bubble indicator was removed
  // (per spec) but autoplay + manual swipe must keep working.
  useEffect(() => {
    if (pageCount <= 1 || autoPaused) return undefined;
    const interval = window.setInterval(() => {
      const scroller = scrollerRef.current;
      if (!scroller) return;
      const next = (currentPageRef.current + 1) % pageCount;
      currentPageRef.current = next;
      scroller.scrollTo({
        left: next * scroller.clientWidth,
        behavior: "smooth",
      });
    }, 4000);

    return () => window.clearInterval(interval);
  }, [autoPaused, pageCount]);

  useEffect(() => {
    return () => {
      if (resumeTimerRef.current) window.clearTimeout(resumeTimerRef.current);
    };
  }, []);

  if (brands.length === 0) {
    return null;
  }

  return (
    <section className="mt-8" aria-labelledby="brand-choice-title">
      <div className="flex items-center justify-between gap-3 px-4">
        <h2 id="brand-choice-title" className="text-[20px] font-black tracking-tight text-slate-900">
          Brand Favorit
        </h2>
        <Link
          href="/brands"
          className="flex h-9 shrink-0 items-center rounded-full px-2 text-[15px] font-bold text-natalo-600 active:opacity-70"
        >
          Lihat semua
        </Link>
      </div>

      <div
        ref={scrollerRef}
        onPointerDown={pauseAutoSlide}
        onTouchStart={pauseAutoSlide}
        onScroll={() => {
          const scroller = scrollerRef.current;
          if (!scroller) return;
          const page = Math.round(scroller.scrollLeft / Math.max(1, scroller.clientWidth));
          currentPageRef.current = Math.min(pageCount - 1, Math.max(0, page));
        }}
        className="scrollbar-hide mt-3 flex snap-x snap-mandatory gap-2.5 overflow-x-auto scroll-smooth px-4 pb-2"
      >
        {brands.map((brand) => (
          <Link
            key={brand.id}
            href={brandProductHref(brand)}
            aria-label={`Lihat produk brand ${brand.name}`}
            className="flex h-[116px] min-w-0 shrink-0 basis-[calc((100%_-_1.25rem)/3)] snap-start flex-col items-center justify-center rounded-2xl border border-[#eef3fb] bg-white px-3 py-3 shadow-sm transition active:scale-[0.97] active:opacity-90"
          >
            <div className="flex h-[54px] w-full items-center justify-center">
              <BrandLogo brand={brand} />
            </div>
            <span className="mt-3 line-clamp-1 max-w-full text-center text-[13px] font-bold leading-tight text-slate-700">
              {brand.name}
            </span>
          </Link>
        ))}
      </div>
    </section>
  );
}
