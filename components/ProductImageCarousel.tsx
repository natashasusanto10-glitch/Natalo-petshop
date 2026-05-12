"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import dynamic from "next/dynamic";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";

// Lazy load ProductImageViewer — pakai Swiper (~50KB) yang cuma di-render
// saat user tap image untuk zoom view. Tanpa dynamic import, Swiper masuk
// initial bundle product detail page. Dengan dynamic, baru download saat
// user benar-benar mau lihat zoom.
const ProductImageViewer = dynamic(
  () => import("@/components/product/ProductImageViewer").then((m) => m.ProductImageViewer),
  { ssr: false },
);

type Props = {
  images: string[];
  alt: string;
  /**
   * Optional view-transition-name untuk slide pertama. Match dengan
   * ProductCard.tsx (`nat-prod-${slug}`) → browser morph thumbnail card
   * jadi hero image saat navigasi list → detail.
   */
  transitionName?: string;
};

/**
 * Carousel gambar produk:
 * - 1:1 ratio, latar putih, sudut rounded di desktop
 * - Swipeable horizontal pakai CSS scroll-snap (native, smooth di mobile)
 * - IntersectionObserver melacak slide yg sedang ditampilkan -> update
 *   counter + dot indicator otomatis saat di-swipe
 * - Counter + dot hanya tampil kalau images.length > 1
 * - Per gambar punya onError fallback (placeholder "NP")
 * - Slide pertama = images[0] = thumbnail "Utama" yg diatur admin
 */
export function ProductImageCarousel({ images, alt, transitionName }: Props) {
  const safeImages = images.filter(Boolean);
  const hasImages = safeImages.length > 0;
  const showIndicators = safeImages.length > 1;

  const containerRef = useRef<HTMLDivElement | null>(null);
  const slideRefs = useRef<(HTMLDivElement | null)[]>([]);
  const [active, setActive] = useState(0);
  const [isImageViewerOpen, setIsImageViewerOpen] = useState(false);
  const [activeImageIndex, setActiveImageIndex] = useState(0);
  const [errored, setErrored] = useState<Record<number, boolean>>({});

  // Pakai IntersectionObserver untuk deteksi slide mana yg sedang di-view.
  // Threshold 0.6 supaya hanya slide yg dominan terlihat yg di-set active.
  useEffect(() => {
    if (!showIndicators || !containerRef.current) return;

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting && entry.intersectionRatio >= 0.6) {
            const idx = Number(
              (entry.target as HTMLElement).dataset.index ?? "-1",
            );
            if (idx >= 0) setActive(idx);
          }
        }
      },
      {
        root: containerRef.current,
        threshold: [0.6],
      },
    );

    for (const slide of slideRefs.current) {
      if (slide) observer.observe(slide);
    }

    return () => observer.disconnect();
  }, [showIndicators, safeImages.length]);

  function goTo(index: number) {
    const slide = slideRefs.current[index];
    if (slide) {
      slide.scrollIntoView({ behavior: "smooth", inline: "start", block: "nearest" });
    }
  }

  function openImageViewer(index: number) {
    setActiveImageIndex(index);
    setIsImageViewerOpen(true);
  }

  // Empty state
  if (!hasImages) {
    return (
      <div className="relative mx-auto aspect-square w-full max-h-[360px] overflow-hidden bg-white md:max-h-none md:rounded-3xl">
        <div className="flex h-full items-center justify-center text-5xl font-black text-gray-200">
          NP
        </div>
      </div>
    );
  }

  return (
    <>
      <div className="relative mx-auto aspect-square w-full max-h-[360px] overflow-hidden bg-white md:max-h-none md:rounded-3xl">
        <div
          ref={containerRef}
          className="flex h-full w-full snap-x snap-mandatory overflow-x-auto scroll-smooth [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
          style={{ scrollSnapType: "x mandatory" }}
        >
          {safeImages.map((src, index) => (
            <div
              key={`${src}-${index}`}
              ref={(el) => {
                slideRefs.current[index] = el;
              }}
              data-index={index}
              className="relative h-full w-full shrink-0 snap-start bg-white"
              style={index === 0 && transitionName ? { viewTransitionName: transitionName } : undefined}
            >
              <button
                type="button"
                aria-label={`Buka foto produk ${index + 1}`}
                onClick={() => openImageViewer(index)}
                className="relative block h-full w-full bg-white text-left"
              >
                {errored[index] ? (
                  <div className="flex h-full w-full items-center justify-center text-5xl font-black text-gray-200">
                    NP
                  </div>
                ) : (
                  <Image
                    src={src}
                    alt={`${alt} - gambar ${index + 1}`}
                    fill
                    sizes="(min-width: 1024px) 50vw, 100vw"
                    className="object-cover"
                    priority={index === 0}
                    placeholder="blur"
                    blurDataURL={IMAGE_BLUR_GRAY}
                    onError={() =>
                      setErrored((prev) => ({ ...prev, [index]: true }))
                    }
                  />
                )}
              </button>
            </div>
          ))}
        </div>

        {showIndicators && (
          <>
            <div className="pointer-events-none absolute bottom-3 right-3 rounded-full bg-black/65 px-2.5 py-1 text-xs font-bold text-white">
              {active + 1}/{safeImages.length}
            </div>

            <div className="absolute inset-x-0 bottom-3 flex justify-center gap-1.5">
              {safeImages.map((image, index) => (
                <button
                  key={`dot-${image}-${index}`}
                  type="button"
                  aria-label={`Lihat foto ${index + 1}`}
                  onClick={() => goTo(index)}
                  className={`h-1.5 rounded-full transition-all ${
                    active === index ? "w-5 bg-white" : "w-1.5 bg-white/60"
                  }`}
                />
              ))}
            </div>
          </>
        )}
      </div>

      <ProductImageViewer
        images={safeImages}
        initialIndex={activeImageIndex}
        open={isImageViewerOpen}
        onClose={() => setIsImageViewerOpen(false)}
      />
    </>
  );
}
