import Image from "next/image";
import Link from "next/link";
import { Suspense } from "react";
import { CartCount } from "@/components/CartCount";
import { NotificationBell } from "@/components/NotificationBell";
import { ProductSearchBar } from "@/components/products/ProductSearchBar";

type CategoryOption = {
  slug: string;
  name: string;
};

type Props = {
  brandName: string;
  categories: CategoryOption[];
  activeBrandName?: string;
  query: string;
  isSearchResult: boolean;
};

/**
 * Chrome katalog khusus MOBILE.
 *
 * Di `md+` seluruhnya disembunyikan: header global desktop sudah menyediakan
 * pencarian, judul dipegang EtalaseBand, dan filter dipegang sidebar. Baris
 * chip lama (kategori/produk-baru/populer) dibuang karena menulis param
 * `new`/`popular` yang tidak lagi menyaring apa pun setelah katalog pindah ke
 * stack search — filter & sortir mobile kini ada di ProductsCatalogClient.
 */
export function ProductCatalogStickyHeader({
  brandName,
  categories: _categories,
  activeBrandName,
  query,
  isSearchResult,
}: Props) {
  const title = activeBrandName ? `Produk ${activeBrandName}` : "Katalog Produk";

  return (
    <div className="produk-sticky-header sticky top-0 z-[1050] -mx-4 mb-3 rounded-b-3xl border-b border-slate-200/80 bg-white px-4 pb-2.5 pt-[calc(0.55rem+env(safe-area-inset-top))] shadow-[0_10px_28px_rgba(15,23,42,0.08)] md:hidden">
      <div className="mb-2 flex min-h-[58px] items-center justify-between gap-3">
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

      <div className="mb-1">
        <h1 className="text-xl font-black tracking-tight text-slate-950">{title}</h1>
      </div>

      <div>
        <Suspense fallback={<div className="h-10 w-full animate-pulse rounded-full bg-gray-100" />}>
          <ProductSearchBar defaultValue={query} showBackButton={isSearchResult} />
        </Suspense>
      </div>
    </div>
  );
}
