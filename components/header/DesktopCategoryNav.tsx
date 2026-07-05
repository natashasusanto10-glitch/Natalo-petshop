"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import {
  readCategoryCache,
  writeCategoryCache,
  isCategoryCacheFresh,
  type CachedCategorySummary,
} from "@/lib/client-performance";

function categoryHref(slug: string) {
  return `/products?kategori=${encodeURIComponent(slug)}`;
}

const STATIC_LINKS = [
  { href: "/brands", label: "Brand" },
  { href: "/products?sort=promo", label: "Promo" },
  { href: "/products?sort=terlaris", label: "Terlaris" },
  { href: "/products?sort=baru", label: "Produk Baru" },
];

export function DesktopCategoryNav() {
  const [cats, setCats] = useState<CachedCategorySummary[]>([]);
  const [open, setOpen] = useState(false);
  const closeTimer = useRef<number | null>(null);

  useEffect(() => {
    const cached = readCategoryCache();
    if (cached) setCats(cached.categories);
    if (!isCategoryCacheFresh(cached)) {
      fetch("/api/categories", { cache: "force-cache" })
        .then((r) => (r.ok ? r.json() : null))
        .then((p) => {
          if (Array.isArray(p?.categories)) {
            setCats(p.categories);
            writeCategoryCache(p.categories);
          }
        })
        .catch(() => {});
    }
  }, []);

  useEffect(() => {
    return () => {
      if (closeTimer.current) window.clearTimeout(closeTimer.current);
    };
  }, []);

  function openNow() {
    if (closeTimer.current) window.clearTimeout(closeTimer.current);
    setOpen(true);
  }
  function closeSoon() {
    closeTimer.current = window.setTimeout(() => setOpen(false), 120);
  }

  return (
    <nav className="hidden border-t border-zinc-100 bg-white md:block">
      <div className="mx-auto flex max-w-[var(--nat-container)] items-center gap-6 px-[var(--nat-gutter)] py-2.5 text-sm font-semibold text-zinc-700">
        <div className="relative" onMouseEnter={openNow} onMouseLeave={closeSoon}>
          <button
            type="button"
            className="inline-flex items-center gap-1.5 rounded-full px-2 py-1 transition hover:text-natalo-600"
            aria-expanded={open}
            aria-haspopup="true"
          >
            <span aria-hidden>☰</span> Kategori
          </button>
          {open && cats.length > 0 && (
            <div className="absolute left-0 top-full z-50 mt-1 grid w-[520px] grid-cols-2 gap-1 rounded-[var(--radius-lg)] border border-zinc-100 bg-white p-3 shadow-[var(--shadow-pop)]">
              {cats.slice(0, 12).map((c) => (
                <Link
                  key={c.id}
                  href={categoryHref(c.slug)}
                  className="truncate rounded-lg px-3 py-2 text-zinc-700 transition hover:bg-natalo-50 hover:text-natalo-700"
                >
                  {c.name}
                </Link>
              ))}
            </div>
          )}
        </div>
        {STATIC_LINKS.map((l) => (
          <Link key={l.href} href={l.href} className="transition hover:text-natalo-600">
            {l.label}
          </Link>
        ))}
      </div>
    </nav>
  );
}
