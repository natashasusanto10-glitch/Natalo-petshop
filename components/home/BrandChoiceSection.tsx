"use client";

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";

export type BrandChoiceItem = {
  id: string | number;
  name: string;
  slug: string;
  logo?: string | null;
};

type BrandChoiceSectionProps = {
  brands: BrandChoiceItem[];
};

function brandHref(brand: BrandChoiceItem) {
  const params = new URLSearchParams();
  params.set("q", brand.name);
  params.set("brand", brand.slug);
  return `/search?${params.toString()}`;
}

function BrandLogo({ brand }: { brand: BrandChoiceItem }) {
  const [failed, setFailed] = useState(false);

  if (!brand.logo || failed) {
    const compactName = brand.name.replace(/\s+/g, " ");
    return (
      <div className="flex h-full w-full items-center justify-center rounded-xl bg-gradient-to-br from-natalo-50 to-white px-3 text-center">
        <span className="line-clamp-2 text-[13px] font-black uppercase leading-tight tracking-[0.02em] text-natalo-700">
          {compactName}
        </span>
      </div>
    );
  }

  return (
    <Image
      src={brand.logo}
      alt={`Logo ${brand.name}`}
      width={96}
      height={48}
      sizes="96px"
      className="max-h-10 w-auto max-w-full object-contain"
      onError={() => setFailed(true)}
    />
  );
}

export function BrandChoiceSection({ brands }: BrandChoiceSectionProps) {
  if (brands.length === 0) return null;

  return (
    <section className="mt-5" aria-labelledby="brand-choice-title">
      <div className="flex items-start justify-between gap-3 px-4">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-natalo-50 text-natalo-600">
              <svg
                aria-hidden="true"
                viewBox="0 0 24 24"
                className="h-4 w-4"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M20.59 13.41 12 22l-9-9V4h9l8.59 8.59a2 2 0 0 1 0 2.82Z" />
                <circle cx="7.5" cy="8.5" r="1.5" />
              </svg>
            </span>
            <h2 id="brand-choice-title" className="text-base font-black text-zinc-900 sm:text-lg">
              Brand Pilihan
            </h2>
          </div>
          <p className="mt-1 text-xs font-semibold text-zinc-500">
            Temukan produk dari brand favoritmu
          </p>
        </div>
        <Link
          href="/products"
          className="shrink-0 pt-1 text-xs font-bold text-blue-600 active:opacity-70"
        >
          Lihat semua
        </Link>
      </div>

      <div className="mt-3 flex snap-x snap-mandatory gap-3 overflow-x-auto scroll-smooth px-4 pb-2 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {brands.map((brand) => (
          <Link
            key={brand.id}
            href={brandHref(brand)}
            aria-label={`Lihat produk brand ${brand.name}`}
            className="flex h-[112px] w-[120px] shrink-0 snap-start flex-col items-center justify-center rounded-2xl border border-[#edf2f7] bg-white p-3 shadow-sm transition active:scale-[0.98] active:opacity-90"
          >
            <div className="flex h-14 w-full items-center justify-center rounded-xl bg-slate-50 px-3">
              <BrandLogo brand={brand} />
            </div>
            <span className="mt-3 line-clamp-1 max-w-full text-center text-[11px] font-extrabold leading-tight text-zinc-600">
              {brand.name}
            </span>
          </Link>
        ))}
      </div>
    </section>
  );
}
