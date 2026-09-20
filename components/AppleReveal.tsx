"use client";

import { useEffect } from "react";

/**
 * Pemicu animasi "apple-reveal" (IntersectionObserver murni, tanpa library).
 * Mount SEKALI per halaman (homepage). Elemen dengan class `apple-reveal`
 * (heading section, kartu produk) start tersembunyi via CSS (SSR-rendered,
 * jadi tanpa flash), lalu mendapat `is-visible` saat ≥15% masuk viewport —
 * sekali saja, observer langsung dilepas (progressive disclosure hemat
 * memori). Stagger antar kartu grid ditangani CSS nth-child di globals.
 *
 * prefers-reduced-motion → semua elemen langsung visible tanpa animasi.
 */
export function AppleReveal() {
  useEffect(() => {
    const elements = Array.from(document.querySelectorAll<HTMLElement>(".apple-reveal"));
    if (elements.length === 0) return undefined;

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      elements.forEach((el) => el.classList.add("is-visible"));
      return undefined;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { root: null, rootMargin: "0px", threshold: 0.15 },
    );
    elements.forEach((el) => observer.observe(el));
    return () => observer.disconnect();
  }, []);

  return null;
}
