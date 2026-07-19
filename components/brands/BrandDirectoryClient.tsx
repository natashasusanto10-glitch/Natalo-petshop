"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { FiArrowLeft, FiSearch } from "react-icons/fi";
import { CartCount } from "@/components/CartCount";
import { EtalaseBand } from "@/components/products/EtalaseBand";
import { brandProductHref, type BrandCatalogItem } from "@/lib/brand-catalog";

function BrandLogo({ brand }: { brand: BrandCatalogItem }) {
  const [failed, setFailed] = useState(false);

  if (!brand.logo || failed) {
    return (
      <div className="flex h-full w-full items-center justify-center px-1 text-center">
        <span className="line-clamp-2 text-[12px] font-black uppercase leading-tight text-natalo-700">
          {brand.name}
        </span>
      </div>
    );
  }

  return (
    <Image
      src={brand.logo}
      alt={`Logo ${brand.name}`}
      width={132}
      height={72}
      sizes="33vw"
      className={`h-auto w-auto object-contain mix-blend-multiply ${brand.imageClass ?? "max-h-[46px] max-w-[104px]"}`}
      onError={() => setFailed(true)}
    />
  );
}

function BrandGridSkeleton() {
  return (
    <div className="grid grid-cols-3 gap-3 sm:grid-cols-4 lg:grid-cols-6">
      {Array.from({ length: 12 }).map((_, index) => (
        <div
          key={index}
          className="h-[112px] animate-pulse rounded-[20px] border border-slate-100 bg-white shadow-sm"
        />
      ))}
    </div>
  );
}

export function BrandDirectoryClient({ brands }: { brands: BrandCatalogItem[] }) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setReady(true);
  }, []);

  const filteredBrands = useMemo(() => {
    const keyword = query.trim().toLowerCase();
    if (!keyword) return brands;
    return brands.filter((brand) => brand.name.toLowerCase().includes(keyword));
  }, [brands, query]);

  function goBack() {
    if (window.history.length > 1) {
      router.back();
      return;
    }
    router.push("/");
  }

  return (
    <main className="min-h-screen bg-slate-50 pb-[calc(7rem+env(safe-area-inset-bottom))]">
      <header className="sticky top-0 z-50 border-b border-slate-100 bg-white/95 pt-[env(safe-area-inset-top)] shadow-[0_8px_22px_rgba(15,23,42,0.06)] backdrop-blur">
        <div className="mx-auto flex h-16 max-w-[var(--nat-container)] items-center gap-3 px-4">
          <button
            type="button"
            onClick={goBack}
            aria-label="Kembali"
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full text-slate-800 transition active:bg-slate-100"
          >
            <FiArrowLeft className="h-5 w-5" aria-hidden="true" />
          </button>
          <h1 className="min-w-0 flex-1 truncate text-xl font-black tracking-tight text-slate-950">
            Semua Brand
          </h1>
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-slate-700">
            <CartCount compact />
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-[var(--nat-container)] px-[var(--nat-gutter)] pt-4">
        <div className="mb-4 hidden md:block">
          <EtalaseBand
            heading="Brand Pilihan"
            tagline="Merek terpercaya yang kami stok — hasil 7 tahun kurasi toko Natalo di Medan."
            breadcrumb={[{ label: "Beranda", href: "/" }, { label: "Brand" }]}
          />
        </div>
        <label className="relative block md:max-w-md">
          <FiSearch
            className="pointer-events-none absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-slate-400"
            aria-hidden="true"
          />
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Cari brand favoritmu..."
            className="h-12 w-full rounded-full border border-slate-200 bg-white pl-11 pr-4 text-sm font-bold text-slate-900 outline-none transition placeholder:text-slate-400 focus:border-natalo-400 focus:ring-4 focus:ring-natalo-100"
          />
        </label>

        <section className="mt-5">
          {!ready ? (
            <BrandGridSkeleton />
          ) : filteredBrands.length === 0 ? (
            <div className="rounded-[24px] border border-dashed border-slate-200 bg-white px-6 py-10 text-center">
              <p className="text-base font-black text-slate-900">Brand tidak ditemukan</p>
              <p className="mt-1 text-sm font-semibold text-slate-500">Coba gunakan kata kunci lain.</p>
            </div>
          ) : (
            <div className="grid grid-cols-3 gap-3 sm:grid-cols-4 lg:grid-cols-6">
              {filteredBrands.map((brand) => (
                <Link
                  key={brand.slug}
                  href={brandProductHref(brand)}
                  className="nat-lit-shelf nat-shelf-line group relative flex h-[112px] min-w-0 flex-col items-center justify-center rounded-[20px] border border-[#E5EAF3] bg-white px-2.5 py-3 shadow-[0_8px_22px_rgba(15,23,42,0.06)] transition active:scale-[0.97] active:opacity-90 sm:hover:border-natalo-200"
                  aria-label={`Lihat produk brand ${brand.name}`}
                >
                  <div className="flex h-[54px] w-full items-center justify-center">
                    <BrandLogo brand={brand} />
                  </div>
                  <span className="mt-3 line-clamp-1 max-w-full text-center text-[12px] font-bold leading-tight text-slate-700">
                    {brand.name}
                  </span>
                </Link>
              ))}
            </div>
          )}
        </section>
      </div>
    </main>
  );
}
