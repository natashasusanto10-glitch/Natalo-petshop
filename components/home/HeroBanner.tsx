"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { heroSlides as defaultSlides, type HeroSlide, type HeroSlideIcon } from "@/data/heroSlides";
import { filterActiveSlides } from "@/lib/filterActiveSlides";

const ROTATE_INTERVAL_MS = 3000;
const RESUME_AFTER_TOUCH_MS = 4000;

export default function HeroBanner({
  slides = defaultSlides,
  intervalMs = ROTATE_INTERVAL_MS,
}: {
  slides?: HeroSlide[];
  intervalMs?: number;
}) {
  const activeSlides = filterActiveSlides(slides);
  const [current, setCurrent] = useState(0);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const total = activeSlides.length;

  useEffect(() => {
    if (current >= total) setCurrent(0);
  }, [current, total]);

  useEffect(() => {
    function stop() {
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
    }

    function start() {
      stop();
      if (total <= 1) return;
      timerRef.current = setInterval(() => {
        setCurrent((value) => (value + 1) % total);
      }, intervalMs);
    }

    start();

    const container = containerRef.current;
    if (!container) return stop;

    let resumeTimeout: ReturnType<typeof setTimeout> | null = null;
    const pause = () => stop();
    const resume = () => start();
    const touchStart = () => {
      stop();
      if (resumeTimeout) clearTimeout(resumeTimeout);
    };
    const touchEnd = () => {
      if (resumeTimeout) clearTimeout(resumeTimeout);
      resumeTimeout = setTimeout(start, RESUME_AFTER_TOUCH_MS);
    };

    container.addEventListener("mouseenter", pause);
    container.addEventListener("mouseleave", resume);
    container.addEventListener("touchstart", touchStart, { passive: true });
    container.addEventListener("touchend", touchEnd, { passive: true });

    return () => {
      stop();
      if (resumeTimeout) clearTimeout(resumeTimeout);
      container.removeEventListener("mouseenter", pause);
      container.removeEventListener("mouseleave", resume);
      container.removeEventListener("touchstart", touchStart);
      container.removeEventListener("touchend", touchEnd);
    };
  }, [total, intervalMs]);

  if (total === 0) return null;

  return (
    <div className="px-4 pt-3">
      <div ref={containerRef} className="relative aspect-[16/9] overflow-hidden rounded-2xl shadow-sm">
        <div
          className="flex h-full transition-transform duration-700 ease-out"
          style={{
            width: `${total * 100}%`,
            transform: `translateX(-${(100 / total) * current}%)`,
          }}
        >
          {activeSlides.map((slide) => (
            <SlideContent key={slide.id} slide={slide} totalSlides={total} />
          ))}
        </div>

        {total > 1 && (
          <div className="absolute inset-x-0 bottom-2 z-10 flex justify-center gap-1.5">
            {activeSlides.map((slide, index) => (
              <button
                key={slide.id}
                type="button"
                onClick={() => setCurrent(index)}
                aria-label={`Slide ${index + 1} dari ${total}`}
                className={`rounded-full transition-all ${
                  index === current ? "h-1.5 w-6 bg-white/90" : "h-1.5 w-1.5 bg-white/45"
                }`}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function SlideContent({ slide, totalSlides }: { slide: HeroSlide; totalSlides: number }) {
  const slideWidth = `${100 / totalSlides}%`;

  if (slide.type === "image") {
    const image = (
      <Image
        src={slide.image}
        alt={slide.imageAlt}
        fill
        className="object-cover"
        sizes="(max-width: 768px) 100vw, 768px"
        priority={slide.priority}
      />
    );

    return (
      <div className="relative shrink-0" style={{ width: slideWidth }}>
        {slide.href ? (
          <Link href={slide.href} className="block h-full w-full">
            {image}
          </Link>
        ) : (
          image
        )}
      </div>
    );
  }

  return (
    <div
      className={`relative flex shrink-0 flex-col justify-center overflow-hidden bg-gradient-to-br p-4 ${slide.background}`}
      style={{ width: slideWidth }}
    >
      <div className="absolute -right-5 -top-5 flex h-24 w-24 items-center justify-center rounded-full bg-white/10 text-white/35">
        <HeroSlideSvg name={slide.icon} className="h-12 w-12" />
      </div>
      <div className="absolute -bottom-8 right-10 h-24 w-24 rounded-full border border-white/15" />

      <div className="relative max-w-[78%]">
        <span className="mb-2 inline-flex items-center gap-1.5 rounded-full bg-white/20 px-2.5 py-1 text-[11px] font-semibold text-white backdrop-blur-sm">
          <HeroSlideSvg name={slide.icon} className="h-3.5 w-3.5" />
          {slide.badge}
        </span>

        <h1 className="mb-1.5 text-base font-extrabold leading-tight text-white">
          {slide.headlineBefore && <>{slide.headlineBefore} </>}
          <span className="text-amber-300">{slide.headlineHighlight}</span>
          {slide.headlineAfter && <> {slide.headlineAfter}</>}
        </h1>

        <p className="mb-2 text-[11px] leading-snug text-white/85">{slide.subtitle}</p>

        <Link
          href={slide.cta.href}
          className={`inline-flex rounded-md px-3 py-1.5 text-[11px] font-bold ${
            slide.cta.bg || "bg-white"
          } ${slide.cta.textColor || "text-natalo-800"}`}
        >
          {slide.cta.text}
          <span aria-hidden="true" className="ml-1">
            &gt;
          </span>
        </Link>
      </div>
    </div>
  );
}

function HeroSlideSvg({ name, className }: { name: HeroSlideIcon; className?: string }) {
  const paths: Record<HeroSlideIcon, React.ReactNode> = {
    award: (
      <>
        <circle cx="12" cy="8" r="4" />
        <path d="m8.5 11.5-1.5 8 5-3 5 3-1.5-8" />
      </>
    ),
    bolt: <path d="M13 2 4 14h7l-1 8 10-13h-7l1-7Z" />,
    fish: (
      <>
        <path d="M3 12s4-6 10-6c4 0 7 6 7 6s-3 6-7 6c-6 0-10-6-10-6Z" />
        <path d="m20 12 2-3v6l-2-3Z" />
        <path d="M8 12h.01" />
      </>
    ),
    gift: (
      <>
        <path d="M4 10h16v10H4z" />
        <path d="M12 10v10" />
        <path d="M3 6h18v4H3z" />
        <path d="M12 6c-1.5-3-5-3-5 0 0 2 3 2 5 0Z" />
        <path d="M12 6c1.5-3 5-3 5 0 0 2-3 2-5 0Z" />
      </>
    ),
    store: (
      <>
        <path d="M4 10h16l-1-5H5l-1 5Z" />
        <path d="M6 10v10h12V10" />
        <path d="M9 20v-6h6v6" />
      </>
    ),
  };

  return (
    <svg
      aria-hidden="true"
      className={className}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
    >
      {paths[name]}
    </svg>
  );
}
