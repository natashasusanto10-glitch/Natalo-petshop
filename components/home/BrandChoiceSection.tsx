"use client";

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";

export type BrandChoiceItem = {
  id: string | number;
  name: string;
  slug: string;
  logo?: string | null;
  imageClass?: string;
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
  const imageClass = brand.imageClass ?? "max-h-[44px] max-w-[100px]";

  if (!brand.logo || failed) {
    const compactName = brand.name.replace(/\s+/g, " ");
    return (
      <div className="flex h-full w-full items-center justify-center px-2 text-center">
        <span className="line-clamp-2 text-[13px] font-black uppercase leading-tight text-natalo-700">
          {compactName}
        </span>
      </div>
    );
  }

  return (
    <Image
      src={brand.logo}
      alt={`Logo ${brand.name}`}
      width={120}
      height={64}
      sizes="122px"
      className={`h-auto w-auto object-contain mix-blend-multiply ${imageClass}`}
      onError={() => setFailed(true)}
    />
  );
}

export function BrandChoiceSection({ brands }: BrandChoiceSectionProps) {
  if (brands.length === 0) return null;

  return (
    <section className="mt-8" aria-labelledby="brand-choice-title">
      <div className="flex items-start justify-between gap-3 px-4">
        <div className="min-w-0">
          <div className="flex items-center gap-3">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-blue-50 text-blue-600">
              <svg
                aria-hidden="true"
                viewBox="0 0 24 24"
                className="h-5 w-5"
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
            <h2 id="brand-choice-title" className="text-[22px] font-bold tracking-tight text-slate-900">
              Brand Pilihan
            </h2>
          </div>
          <p className="mt-2 text-[15px] text-slate-500">
            Temukan produk dari brand favoritmu
          </p>
        </div>
        <Link
          href="/products"
          className="mt-2 flex shrink-0 items-center gap-1 text-[15px] font-semibold text-blue-600 active:opacity-70"
        >
          Lihat semua
          <span className="text-lg leading-none">›</span>
        </Link>
      </div>

      <div className="scrollbar-hide mt-3 flex snap-x snap-mandatory gap-3 overflow-x-auto scroll-smooth px-4 pb-2">
        {brands.map((brand) => (
          <Link
            key={brand.id}
            href={brandHref(brand)}
            aria-label={`Lihat produk brand ${brand.name}`}
            className="flex h-[124px] w-[122px] shrink-0 snap-start flex-col items-center justify-center rounded-[22px] border border-slate-100 bg-white px-3 py-4 shadow-sm transition active:scale-[0.97] active:opacity-90"
          >
            <div className="flex h-[62px] w-full items-center justify-center">
              <BrandLogo brand={brand} />
            </div>
            <span className="mt-3 line-clamp-1 max-w-full text-center text-[14px] font-semibold leading-tight text-slate-700">
              {brand.name}
            </span>
          </Link>
        ))}
      </div>
    </section>
  );
}
