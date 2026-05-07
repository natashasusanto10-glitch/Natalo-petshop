import Link from "next/link";
import { CartCount } from "./CartCount";
import { MemberAccountLink } from "./MemberAccountLink";
import { SearchBar } from "./SearchBar";

export function Header() {
  const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Pet Shop";

  return (
    <header className="sticky top-0 z-50 bg-white shadow-sm">
      <div className="mx-auto max-w-6xl px-3 py-3 sm:px-4 sm:py-4">
        {/* Top row: logo + nav + actions */}
        <div className="flex items-center justify-between gap-3">
          {/* Logo */}
          <Link href="/" className="flex min-w-0 items-center gap-2">
            <span className="text-2xl">🐾</span>
            <span className="truncate text-sm font-bold text-gray-900 sm:text-base">
              {brand}
            </span>
          </Link>

          {/* Search bar — desktop (di tengah) */}
          <div className="hidden flex-1 px-6 md:block lg:px-12">
            <SearchBar />
          </div>

          {/* Nav */}
          <nav className="hidden items-center gap-6 text-sm font-medium text-gray-700 md:flex">
            <Link href="/" className="transition hover:text-natalo-600">
              Beranda
            </Link>
            <Link href="/products" className="transition hover:text-natalo-600">
              Produk
            </Link>
            <Link href="/tentang-kami" className="transition hover:text-natalo-600">
              Tentang
            </Link>
          </nav>

          {/* Right actions */}
          <div className="flex shrink-0 items-center gap-2 sm:gap-4">
            <CartCount />
            <MemberAccountLink />
          </div>
        </div>

        {/* Search bar — mobile (full-width di bawah) */}
        <div className="mt-3 md:hidden">
          <SearchBar />
        </div>
      </div>
    </header>
  );
}
