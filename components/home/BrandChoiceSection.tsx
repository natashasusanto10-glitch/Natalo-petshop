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
  const [activePage, setActivePage] = useState(0);
  const [autoPaused, setAutoPaused] = useState(false);
  const pageCount = useMemo(() => Math.max(1, Math.ceil(brands.length / 3)), [brands.length]);

  const scrollToPage = useCallback((page: number) => {
    const scroller = scrollerRef.current;
    if (!scroller) return;
    const nextPage = ((page % pageCount) + pageCount) % pageCount;
    scroller.scrollTo({
      left: nextPage * scroller.clientWidth,
      behavior: "smooth",
    });
    setActivePage(nextPage);
  }, [pageCount]);

  const pauseAutoSlide = useCallback(() => {
    setAutoPaused(true);
    if (resumeTimerRef.current) window.clearTimeout(resumeTimerRef.current);
    resumeTimerRef.current = window.setTimeout(() => {
      setAutoPaused(false);
    }, 5500);
  }, []);

  useEffect(() => {
    if (pageCount <= 1 || autoPaused) return undefined;
    const interval = window.setInterval(() => {
      setActivePage((current) => {
        const next = (current + 1) % pageCount;
        const scroller = scrollerRef.current;
        if (scroller) {
          scroller.scrollTo({
            left: next * scroller.clientWidth,
            behavior: "smooth",
          });
        }
        return next;
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
    return (
      <section className="mt-8 px-4" aria-labelledby="brand-choice-title">
        <div className="flex items-center justify-between">
          <h2 id="brand-choice-title" className="text-[20px] font-black tracking-tight text-slate-900">
            Brand Favorit
          </h2>
          <div className="h-5 w-20 animate-pulse rounded-full bg-slate-100" />
        </div>
        <div className="mt-3 grid grid-cols-3 gap-3">
          {Array.from({ length: 3 }).map((_, index) => (
            <div key={index} className="h-[116px] animate-pulse rounded-[20px] border border-slate-100 bg-white shadow-sm" />
          ))}
        </div>
      </section>
    );
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
          setActivePage(Math.min(pageCount - 1, Math.max(0, page)));
        }}
        className="scrollbar-hide mx-4 mt-3 flex snap-x snap-mandatory gap-3 overflow-x-auto scroll-smooth pb-2"
      >
        {brands.map((brand) => (
          <Link
            key={brand.id}
            href={brandProductHref(brand)}
            aria-label={`Lihat produk brand ${brand.name}`}
            className="flex h-[116px] min-w-0 shrink-0 basis-[calc((100%_-_1.5rem)/3)] snap-start flex-col items-center justify-center rounded-[20px] border border-[#E5EAF3] bg-white px-3 py-3 shadow-[0_8px_22px_rgba(15,23,42,0.06)] transition active:scale-[0.97] active:opacity-90"
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

      {pageCount > 1 && (
        <div className="mt-2 flex justify-center gap-1.5" aria-label="Posisi brand favorit">
          {Array.from({ length: pageCount }).map((_, index) => (
            <button
              key={index}
              type="button"
              onClick={() => {
                pauseAutoSlide();
                scrollToPage(index);
              }}
              aria-label={`Slide brand ${index + 1}`}
              className={`h-1.5 rounded-full transition-all ${
                activePage === index ? "w-4 bg-natalo-600" : "w-1.5 bg-slate-300"
              }`}
            />
          ))}
        </div>
      )}
    </section>
  );
}
