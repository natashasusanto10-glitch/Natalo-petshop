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
   * jadi hero image saat navigasi list → detail. Diterapkan ke slide
   * index 0 apapun jenisnya (video atau gambar) supaya konsisten dengan
   * ProductCard yang menaruh viewTransitionName di container media,
   * bukan spesifik ke <Image>/<video>.
   */
  transitionName?: string;
  /** Video produk (Bunny) — hanya dikirim caller saat status "ready".
   *  Saat ada, jadi slide #0 galeri (sebelum semua gambar). */
  video?: {
    mp4Url: string;
    thumbnailUrl: string;
    durationSec: number | null;
  };
};

type Slide = { kind: "video" } | { kind: "image"; src: string };

/** Format detik → "mm:ss". null/invalid → null (caller sembunyikan badge). */
function formatClock(totalSeconds: number | null): string | null {
  if (totalSeconds == null || !Number.isFinite(totalSeconds) || totalSeconds < 0) {
    return null;
  }
  const total = Math.round(totalSeconds);
  const minutes = Math.floor(total / 60);
  const seconds = total % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

/**
 * Carousel gambar produk:
 * - 1:1 ratio, latar putih, sudut rounded di desktop
 * - Swipeable horizontal pakai CSS scroll-snap (native, smooth di mobile)
 * - IntersectionObserver melacak slide yg sedang ditampilkan -> update
 *   counter + dot indicator otomatis saat di-swipe
 * - Counter + dot hanya tampil kalau ada lebih dari 1 slide (video + gambar
 *   dihitung bersama)
 * - Per gambar punya onError fallback (placeholder "NP")
 * - Kalau prop `video` ada, slide #0 = video (thumbnail + tombol play besar,
 *   manual — tidak autoplay). Gambar mengikuti sebagai slide 1+. Slide
 *   pertama tanpa video = images[0] = thumbnail "Utama" yg diatur admin.
 * - Video di-pause otomatis saat user swipe ke slide lain.
 * - Zoom viewer (ProductImageViewer) HANYA untuk slide gambar — index-nya
 *   dipetakan dari index slide (dikurangi 1 kalau ada slide video).
 */
export function ProductImageCarousel({ images, alt, transitionName, video }: Props) {
  const safeImages = images.filter(Boolean);
  const imageIndexOffset = video ? 1 : 0;

  const slides: Slide[] = [
    ...(video ? [{ kind: "video" as const }] : []),
    ...safeImages.map((src) => ({ kind: "image" as const, src })),
  ];
  const showIndicators = slides.length > 1;

  const containerRef = useRef<HTMLDivElement | null>(null);
  const slideRefs = useRef<(HTMLDivElement | null)[]>([]);
  const videoElRef = useRef<HTMLVideoElement | null>(null);
  const [active, setActive] = useState(0);
  const [videoPlaying, setVideoPlaying] = useState(false);
  const [videoErrored, setVideoErrored] = useState(false);
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
  }, [showIndicators, slides.length]);

  // Video slide = selalu index 0 (kalau ada). Pause otomatis begitu user
  // swipe ke slide lain — video tetap "manual" (tidak autoplay lagi kalau
  // user swipe balik, cukup di-pause).
  useEffect(() => {
    if (video && active !== 0) {
      videoElRef.current?.pause();
    }
  }, [active, video]);

  // Mulai play begitu user klik tombol ▶ — dilakukan di effect (bukan
  // langsung di handler klik) supaya <video> sudah ter-mount di DOM saat
  // .play() dipanggil (videoPlaying baru jadi true setelah re-render).
  useEffect(() => {
    if (videoPlaying) {
      videoElRef.current?.play().catch(() => {
        // Autoplay/permission gagal — user masih bisa pakai native controls.
      });
    }
  }, [videoPlaying]);

  function goTo(index: number) {
    const slide = slideRefs.current[index];
    if (slide) {
      slide.scrollIntoView({ behavior: "smooth", inline: "start", block: "nearest" });
    }
  }

  function openImageViewer(imageIndex: number) {
    setActiveImageIndex(imageIndex);
    setIsImageViewerOpen(true);
  }

  // Empty state — tidak ada video maupun gambar sama sekali.
  if (slides.length === 0) {
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
          {slides.map((slide, index) => {
            const slideStyle =
              index === 0 && transitionName ? { viewTransitionName: transitionName } : undefined;

            if (slide.kind === "video") {
              if (!video) return null; // tidak mungkin — dijaga oleh guard di atas
              const durationLabel = formatClock(video.durationSec);
              const showVideoEl = videoPlaying && !videoErrored;

              return (
                <div
                  key="video-slide"
                  ref={(el) => {
                    slideRefs.current[index] = el;
                  }}
                  data-index={index}
                  className="relative h-full w-full shrink-0 snap-start bg-black"
                  style={slideStyle}
                >
                  {showVideoEl ? (
                    <video
                      ref={videoElRef}
                      src={video.mp4Url}
                      controls
                      playsInline
                      className="h-full w-full object-contain bg-black"
                      onError={() => {
                        setVideoErrored(true);
                        setVideoPlaying(false);
                      }}
                    />
                  ) : (
                    <button
                      type="button"
                      aria-label="Putar video produk"
                      onClick={() => {
                        setVideoErrored(false);
                        setVideoPlaying(true);
                      }}
                      className="relative block h-full w-full bg-white text-left"
                    >
                      <Image
                        src={video.thumbnailUrl}
                        alt={`${alt} - video produk`}
                        fill
                        sizes="(min-width: 1024px) 50vw, 100vw"
                        className="object-cover"
                        priority
                        placeholder="blur"
                        blurDataURL={IMAGE_BLUR_GRAY}
                      />

                      <span className="pointer-events-none absolute left-3 top-3 rounded-full bg-black/65 px-2.5 py-1 text-xs font-bold text-white">
                        Video
                      </span>

                      {durationLabel && (
                        <span className="pointer-events-none absolute right-3 top-3 rounded-full bg-black/65 px-2.5 py-1 text-xs font-bold text-white">
                          {durationLabel}
                        </span>
                      )}

                      <span className="pointer-events-none absolute inset-0 flex items-center justify-center">
                        <span className="flex h-16 w-16 items-center justify-center rounded-full bg-black/55 text-white">
                          <svg
                            viewBox="0 0 24 24"
                            fill="currentColor"
                            className="h-8 w-8"
                            aria-hidden="true"
                          >
                            <path d="M8 5v14l11-7z" />
                          </svg>
                        </span>
                      </span>
                    </button>
                  )}
                </div>
              );
            }

            const imageIndex = index - imageIndexOffset;

            return (
              <div
                key={`${slide.src}-${index}`}
                ref={(el) => {
                  slideRefs.current[index] = el;
                }}
                data-index={index}
                className="relative h-full w-full shrink-0 snap-start bg-white"
                style={slideStyle}
              >
                <button
                  type="button"
                  aria-label={`Buka foto produk ${imageIndex + 1}`}
                  onClick={() => openImageViewer(imageIndex)}
                  className="relative block h-full w-full bg-white text-left"
                >
                  {errored[index] ? (
                    <div className="flex h-full w-full items-center justify-center text-5xl font-black text-gray-200">
                      NP
                    </div>
                  ) : (
                    <Image
                      src={slide.src}
                      alt={`${alt} - gambar ${imageIndex + 1}`}
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
            );
          })}
        </div>

        {showIndicators && (
          <>
            <div className="pointer-events-none absolute bottom-3 right-3 rounded-full bg-black/65 px-2.5 py-1 text-xs font-bold text-white">
              {active + 1}/{slides.length}
            </div>

            <div className="absolute inset-x-0 bottom-3 flex justify-center gap-1.5">
              {slides.map((_, index) => (
                <button
                  key={`dot-${index}`}
                  type="button"
                  aria-label={`Lihat slide ${index + 1}`}
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
