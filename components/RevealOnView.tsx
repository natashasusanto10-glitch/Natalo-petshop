"use client";

import { useEffect, useRef, useState } from "react";

type Props = {
  children: React.ReactNode;
  className?: string;
  /** Delay transisi ms — untuk stagger ringan antar-section. */
  delay?: number;
};

/**
 * Reveal-on-scroll sekali pakai: elemen fade-in + geser naik saat pertama
 * kali masuk viewport (IntersectionObserver, langsung disconnect setelah
 * tampil). Subtle by design — opacity 0→1 + translateY 16px, 500ms
 * ease-out-quart, hanya transform/opacity (GPU, 60 FPS).
 *
 * - prefers-reduced-motion → langsung tampil tanpa animasi.
 * - Dipakai untuk section homepage di bawah fold; jangan dipakai untuk
 *   hero/konten above-the-fold (merusak LCP).
 */
export function RevealOnView({ children, className = "", delay = 0 }: Props) {
  const ref = useRef<HTMLDivElement | null>(null);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return undefined;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setShown(true);
      return undefined;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          setShown(true);
          observer.disconnect();
        }
      },
      // Muncul sedikit sebelum benar-benar kelihatan supaya animasinya
      // selesai pas elemen masuk area pandang.
      { rootMargin: "0px 0px -8% 0px", threshold: 0.05 },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={ref}
      style={delay ? { transitionDelay: `${delay}ms` } : undefined}
      className={`${className} transition-[opacity,transform] duration-500 [transition-timing-function:cubic-bezier(0.25,1,0.5,1)] ${
        shown ? "translate-y-0 opacity-100" : "translate-y-4 opacity-0"
      }`}
    >
      {children}
    </div>
  );
}
