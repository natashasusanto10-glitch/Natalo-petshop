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
 * PENTING: konten yang muncul BELAKANGAN — batch infinite scroll section
 * Jelajahi menambah HomeProductCard (ber-class apple-reveal) setelah mount —
 * di-observe lewat MutationObserver. Tanpa ini kartu baru tersembunyi
 * selamanya (opacity 0, tak pernah dapat is-visible) → halaman tampak
 * blank saat di-scroll (bug production 20 Sep 2026).
 *
 * prefers-reduced-motion / browser tanpa IntersectionObserver → semua
 * elemen langsung visible tanpa animasi.
 */
export function AppleReveal() {
  useEffect(() => {
    const revealNow = (el: Element) => el.classList.add("is-visible");
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced || typeof IntersectionObserver === "undefined") {
      document.querySelectorAll(".apple-reveal").forEach(revealNow);
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

    function scan() {
      // :not(.is-visible) → elemen yang sudah tampil tak disentuh lagi.
      document
        .querySelectorAll<HTMLElement>(".apple-reveal:not(.is-visible)")
        .forEach((el) => observer.observe(el));
    }
    scan();

    // scan() hanya observe (tidak menulis DOM) dan attribute change
    // (is-visible) tidak dikonfigurasi → tidak ada loop mutasi.
    const mutation = new MutationObserver(() => scan());
    mutation.observe(document.body, { childList: true, subtree: true });

    return () => {
      observer.disconnect();
      mutation.disconnect();
    };
  }, []);

  return null;
}
