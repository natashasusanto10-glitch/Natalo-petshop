import Image from "next/image";
import Link from "next/link";
import { Suspense } from "react";
import { CartCount } from "@/components/CartCount";
import { NotificationBell } from "@/components/NotificationBell";
import { ProductFilterChips } from "@/components/products/ProductFilterChips";
import { ProductSearchBar } from "@/components/products/ProductSearchBar";
import type { NewProductFilter, PopularFilter } from "@/lib/products";

type CategoryOption = {
  slug: string;
  name: string;
};

type Props = {
  brandName: string;
  categories: CategoryOption[];
  activeBrandName?: string;
  query: string;
  activeCategory: string | null;
  activeNewFilter: NewProductFilter | null;
  activePopularFilter: PopularFilter | null;
  isSearchResult: boolean;
};

export function ProductCatalogStickyHeader({
  brandName,
  categories,
  activeBrandName,
  query,
  activeCategory,
  activeNewFilter,
  activePopularFilter,
  isSearchResult,
}: Props) {
  const title = activeBrandName ? `Produk ${activeBrandName}` : "Katalog Produk";

  return (
    <div className="sticky top-0 z-50 -mx-4 mb-3 rounded-b-3xl bg-white px-4 pb-2.5 pt-[calc(0.55rem+env(safe-area-inset-top))] shadow-[0_10px_28px_rgba(15,23,42,0.08)] md:static md:mx-0 md:mb-5 md:rounded-none md:bg-transparent md:px-0 md:pb-0 md:pt-0 md:shadow-none">
      <div className="mb-2 flex min-h-[58px] items-center justify-between gap-3 md:hidden">
        <Link href="/" aria-label={brandName} className="flex min-w-0 shrink-0 items-center">
          <Image
            src="/logo.png"
            alt={brandName}
            width={600}
            height={196}
            priority
            sizes="150px"
            className="h-10 w-auto max-w-[150px]"
          />
        </Link>

        <div className="flex shrink-0 items-center gap-1.5">
          <NotificationBell compact />
          <CartCount compact />
        </div>
      </div>

      {activeBrandName && (
        <div className="mb-3">
          <h1 className="text-2xl font-black tracking-tight text-slate-950">{title}</h1>
          <p className="mt-1 text-sm font-semibold text-slate-500">
            Produk dari brand pilihanmu.
          </p>
        </div>
      )}

      <div className="mb-1.5">
        <Suspense fallback={<div className="h-10 w-full animate-pulse rounded-full bg-gray-100" />}>
          <ProductSearchBar defaultValue={query} showBackButton={isSearchResult} />
        </Suspense>
      </div>

      <Suspense fallback={<div className="h-9 w-full animate-pulse rounded-full bg-gray-100" />}>
        <ProductFilterChips
          categories={categories}
          activeCategory={activeCategory}
          activeNewFilter={activeNewFilter}
          activePopularFilter={activePopularFilter}
        />
      </Suspense>
    </div>
  );
}
