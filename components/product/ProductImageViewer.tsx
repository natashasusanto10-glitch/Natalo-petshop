"use client";

import Image from "next/image";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { Swiper as SwiperType } from "swiper";
import { Keyboard, Zoom } from "swiper/modules";
import { Swiper, SwiperSlide } from "swiper/react";

type ProductImageViewerProps = {
  images: string[];
  initialIndex: number;
  open: boolean;
  onClose: () => void;
};

const CLOSE_ANIMATION_MS = 180;

export function ProductImageViewer({
  images,
  initialIndex,
  open,
  onClose,
}: ProductImageViewerProps) {
  const safeImages = useMemo(() => images.filter(Boolean), [images]);
  const total = safeImages.length;
  const safeInitialIndex =
    total > 0 ? Math.min(Math.max(initialIndex, 0), total - 1) : 0;

  const swiperRef = useRef<SwiperType | null>(null);
  const closeTimerRef = useRef<number | null>(null);
  const touchStartRef = useRef<{ x: number; y: number } | null>(null);
  const [mounted, setMounted] = useState(false);
  const [activeIndex, setActiveIndex] = useState(safeInitialIndex);
  const [isClosing, setIsClosing] = useState(false);
  const [errored, setErrored] = useState<Record<number, boolean>>({});

  const requestClose = useCallback(() => {
    if (isClosing) return;

    setIsClosing(true);
    closeTimerRef.current = window.setTimeout(() => {
      onClose();
      setIsClosing(false);
    }, CLOSE_ANIMATION_MS);
  }, [isClosing, onClose]);

  useEffect(() => {
    setMounted(true);
    return () => {
      if (closeTimerRef.current) {
        window.clearTimeout(closeTimerRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (!open) {
      setIsClosing(false);
      return;
    }

    setActiveIndex(safeInitialIndex);
    window.requestAnimationFrame(() => {
      swiperRef.current?.slideTo(safeInitialIndex, 0);
      swiperRef.current?.zoom?.out();
    });
  }, [open, safeInitialIndex]);

  useEffect(() => {
    if (!open) return;

    const previousBodyOverflow = document.body.style.overflow;
    const previousHtmlOverflow = document.documentElement.style.overflow;

    document.body.style.overflow = "hidden";
    document.documentElement.style.overflow = "hidden";
    document.body.classList.add("product-image-viewer-open");

    return () => {
      document.body.style.overflow = previousBodyOverflow;
      document.documentElement.style.overflow = previousHtmlOverflow;
      document.body.classList.remove("product-image-viewer-open");
    };
  }, [open]);

  useEffect(() => {
    if (!open) return;

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault();
        requestClose();
      }
    }

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [open, requestClose]);

  if (!mounted || !open || total === 0) return null;

  const viewer = (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Galeri foto produk"
      className={`product-image-viewer fixed inset-0 z-[9999] flex h-[100dvh] min-h-screen flex-col overflow-hidden bg-black text-white transition duration-200 ${
        isClosing ? "opacity-0" : "opacity-100"
      }`}
      style={{
        paddingTop: "env(safe-area-inset-top)",
        paddingBottom: "env(safe-area-inset-bottom)",
      }}
      onTouchStart={(event) => {
        const touch = event.touches[0];
        if (touch) touchStartRef.current = { x: touch.clientX, y: touch.clientY };
      }}
      onTouchEnd={(event) => {
        const start = touchStartRef.current;
        const touch = event.changedTouches[0];
        touchStartRef.current = null;
        if (!start || !touch) return;

        const deltaX = touch.clientX - start.x;
        const deltaY = touch.clientY - start.y;
        const zoomScale = swiperRef.current?.zoom?.scale ?? 1;

        if (zoomScale <= 1.02 && deltaY > 95 && Math.abs(deltaY) > Math.abs(deltaX) * 1.35) {
          requestClose();
        }
      }}
    >
      <div
        className="pointer-events-none absolute inset-x-0 top-0 z-10 flex h-16 items-center justify-between px-3"
        style={{ paddingTop: "env(safe-area-inset-top)" }}
      >
        <button
          type="button"
          aria-label="Kembali"
          onClick={requestClose}
          className="pointer-events-auto flex h-11 w-11 items-center justify-center rounded-full text-white active:bg-white/10"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.25"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="h-7 w-7"
          >
            <path d="M15 18l-6-6 6-6" />
          </svg>
        </button>

        <div className="pointer-events-none absolute inset-x-0 flex justify-center">
          <span className="rounded-full bg-black/35 px-3 py-1 text-sm font-bold leading-none text-white">
            {activeIndex + 1} / {total}
          </span>
        </div>

        <button
          type="button"
          aria-label="Tutup galeri"
          onClick={requestClose}
          className="pointer-events-auto flex h-11 w-11 items-center justify-center rounded-full text-white active:bg-white/10"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.25"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="h-7 w-7"
          >
            <path d="M18 6 6 18" />
            <path d="m6 6 12 12" />
          </svg>
        </button>
      </div>

      <div
        className={`flex min-h-0 flex-1 items-center justify-center transition duration-200 ${
          isClosing ? "scale-[0.985]" : "scale-100"
        }`}
      >
        <Swiper
          modules={[Keyboard, Zoom]}
          className="h-full w-full"
          initialSlide={safeInitialIndex}
          keyboard={{ enabled: true }}
          resistanceRatio={0.75}
          slidesPerView={1}
          spaceBetween={0}
          zoom={{ maxRatio: 3, minRatio: 1, toggle: true }}
          onSwiper={(swiper) => {
            swiperRef.current = swiper;
          }}
          onSlideChange={(swiper) => {
            swiper.zoom?.out();
            setActiveIndex(swiper.activeIndex);
          }}
        >
          {safeImages.map((src, index) => (
            <SwiperSlide key={`${src}-${index}`}>
              <div className="swiper-zoom-container">
                {errored[index] ? (
                  <div className="flex h-full w-full items-center justify-center text-5xl font-black text-white/25">
                    NP
                  </div>
                ) : (
                  <Image
                    src={src}
                    alt={`Foto produk ${index + 1}`}
                    width={1400}
                    height={1400}
                    sizes="100vw"
                    className="max-h-[calc(100dvh-96px)] w-auto max-w-full select-none object-contain"
                    priority={index === safeInitialIndex}
                    draggable={false}
                    onError={() =>
                      setErrored((prev) => ({ ...prev, [index]: true }))
                    }
                  />
                )}
              </div>
            </SwiperSlide>
          ))}
        </Swiper>
      </div>
    </div>
  );

  return createPortal(viewer, document.body);
}
