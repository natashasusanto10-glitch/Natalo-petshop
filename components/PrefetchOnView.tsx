"use client";

import Link, { type LinkProps } from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, type ReactNode } from "react";

type Props = Omit<LinkProps, "href"> & {
  href: string;
  children: ReactNode;
  className?: string;
  /** Threshold IO untuk trigger prefetch. Default 0.1 (10% visible). */
  threshold?: number;
  /** Margin sebelum element masuk viewport. Default "200px" — prefetch
   *  saat element 200px sebelum visible. */
  rootMargin?: string;
};

/**
 * Wrapper <Link> yang auto-prefetch route saat element terlihat di viewport.
 * Berguna untuk daftar produk di luar viewport (related products di PDP,
 * grid panjang di katalog) — saat user scroll mendekati card, route data
 * udah pre-fetched, navigation jadi terasa instan saat tap.
 *
 * Pakai IntersectionObserver dengan rootMargin "200px" supaya prefetch
 * dimulai sebelum card benar-benar visible. Disconnect setelah prefetch
 * dipanggil supaya cuma 1x per element (hindari spam).
 *
 * Force-dynamic routes (force-dynamic page seperti /products/[slug])
 * memang tidak di-prefetch oleh default Link, tapi router.prefetch()
 * tetap akan **prepare** server fetch (warm cache + jit compile) — masih
 * ada manfaat untuk warming up the route segment.
 */
export function PrefetchOnView({
  href,
  children,
  className,
  threshold = 0.1,
  rootMargin = "200px",
  ...linkProps
}: Props) {
  const router = useRouter();
  const ref = useRef<HTMLAnchorElement | null>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === "undefined") return;

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            router.prefetch(href);
            // 1x prefetch sudah cukup — disconnect supaya tidak fire ulang
            // saat user scroll bolak-balik.
            observer.disconnect();
            break;
          }
        }
      },
      { threshold, rootMargin },
    );

    observer.observe(el);
    return () => observer.disconnect();
  }, [href, router, threshold, rootMargin]);

  return (
    <Link ref={ref} href={href} className={className} {...linkProps}>
      {children}
    </Link>
  );
}
