import Link from "next/link";
import { CartCount } from "./CartCount";

export function Header() {
  const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Pet Shop";

  return (
    <header className="sticky top-0 z-50 bg-white shadow-sm">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2">
          <span className="text-2xl">🐾</span>
          <span className="font-bold text-gray-900">{brand}</span>
        </Link>

        {/* Nav */}
        <nav className="hidden items-center gap-8 text-sm font-medium text-gray-700 md:flex">
          <Link href="/" className="transition hover:text-orange-500">
            Beranda
          </Link>
          <Link href="/products" className="transition hover:text-orange-500">
            Produk
          </Link>
          <Link href="/member" className="transition hover:text-orange-500">
            Member
          </Link>
        </nav>

        {/* Right actions */}
        <div className="flex items-center gap-5">
          <CartCount />
          <Link
            href="/member"
            className="hidden rounded-full bg-orange-500 px-5 py-2 text-sm font-semibold text-white transition hover:bg-orange-600 md:inline-flex"
          >
            Masuk
          </Link>
          {/* Mobile menu burger */}
          <Link href="/cart" className="flex items-center gap-1 text-sm font-medium text-gray-700 md:hidden">
            Keranjang
          </Link>
        </div>
      </div>
    </header>
  );
}
