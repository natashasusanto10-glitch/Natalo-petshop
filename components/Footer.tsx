import Link from "next/link";
import { OperatingHours } from "@/components/OperatingHours";

export function Footer() {
  const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Pet Shop";
  const wa = process.env.NEXT_PUBLIC_WHATSAPP_NUMBER || "";

  return (
    <footer className="relative mt-16 overflow-hidden bg-gray-50">
      {/* Paw watermarks */}
      <div className="pointer-events-none absolute inset-0 select-none">
        {["top-6 left-10 opacity-5 text-7xl", "top-20 right-24 opacity-5 text-5xl rotate-12", "bottom-10 left-1/3 opacity-5 text-6xl -rotate-12", "bottom-6 right-12 opacity-5 text-8xl rotate-6"].map((cls, i) => (
          <span key={i} className={`absolute ${cls}`}>🐾</span>
        ))}
      </div>

      <div className="relative mx-auto max-w-6xl px-4 py-12">
        <div className="grid gap-10 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-5">
          {/* Brand */}
          <div className="md:col-span-3 lg:col-span-1">
            <Link href="/" className="flex items-center gap-2">
              <span className="text-xl">🐾</span>
              <span className="font-bold text-gray-900">{brand}</span>
            </Link>
            <p className="mt-3 text-sm leading-relaxed text-gray-500">
              Toko hewan peliharaan terpercaya. Produk berkualitas untuk sahabat berbulu kamu.
            </p>
            <div className="mt-4 flex gap-3">
              {[
                {
                  label: "Instagram",
                  href: "https://www.instagram.com/natalopetshop/",
                  icon: (
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-4 w-4">
                      <rect x="2" y="2" width="20" height="20" rx="5" />
                      <path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z" />
                      <line x1="17.5" y1="6.5" x2="17.51" y2="6.5" />
                    </svg>
                  ),
                },
                {
                  label: "WhatsApp",
                  href: `https://wa.me/${wa.replace("+", "")}`,
                  icon: (
                    <svg viewBox="0 0 24 24" fill="currentColor" className="h-4 w-4">
                      <path d="M20.52 3.48A12 12 0 0 0 3.5 20.36L2 22l1.69-1.55A12 12 0 1 0 20.52 3.48Zm-8.4 18a10 10 0 0 1-5.1-1.4l-.36-.21-3.06.86.82-3-.24-.38a10 10 0 1 1 7.94 4.13Zm5.5-7.5c-.3-.15-1.78-.88-2-1s-.5-.15-.7.15-.82 1-1 1.2-.36.22-.66.07a8.2 8.2 0 0 1-2.4-1.48 9.05 9.05 0 0 1-1.66-2.07c-.17-.3 0-.46.13-.61s.3-.36.45-.54a2.1 2.1 0 0 0 .3-.5.55.55 0 0 0 0-.53c-.07-.15-.7-1.67-.95-2.28s-.5-.52-.7-.53h-.6a1.16 1.16 0 0 0-.83.39 3.5 3.5 0 0 0-1.1 2.6 6.07 6.07 0 0 0 1.27 3.23 13.92 13.92 0 0 0 5.34 4.7c.74.32 1.32.5 1.78.65a4.3 4.3 0 0 0 2 .12 3.24 3.24 0 0 0 2.13-1.5 2.65 2.65 0 0 0 .19-1.5c-.07-.13-.27-.2-.57-.35Z" />
                    </svg>
                  ),
                },
                {
                  label: "TikTok Natalo Petshop",
                  href: "https://www.tiktok.com/@natalopetshop",
                  icon: (
                    <svg viewBox="0 0 24 24" fill="currentColor" className="h-5 w-5" aria-hidden="true">
                      <path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 0 1-2.88 2.5 2.89 2.89 0 0 1-2.89-2.89 2.89 2.89 0 0 1 2.89-2.89c.28 0 .54.04.79.1V9.01a6.33 6.33 0 0 0-.79-.05 6.34 6.34 0 0 0-6.34 6.34 6.34 6.34 0 0 0 6.34 6.34 6.34 6.34 0 0 0 6.33-6.34V8.69a8.18 8.18 0 0 0 4.78 1.52V6.76a4.85 4.85 0 0 1-1.01-.07Z" />
                    </svg>
                  ),
                },
              ].map((s) => (
                <a
                  key={s.label}
                  href={s.href}
                  target="_blank"
                  rel="noreferrer"
                  aria-label={s.label}
                  className="flex h-9 w-9 items-center justify-center rounded-full border border-gray-200 bg-white text-gray-600 transition hover:border-blue-500 hover:text-blue-600"
                >
                  {s.icon}
                </a>
              ))}
            </div>
          </div>

          {/* Toko */}
          <div>
            <p className="font-semibold text-gray-900">Toko</p>
            <ul className="mt-4 space-y-2 text-sm text-gray-500">
              <li><Link href="/products" className="transition hover:text-blue-500">Semua Produk</Link></li>
              <li><Link href="/wishlist" className="transition hover:text-blue-500">Wishlist</Link></li>
              <li><Link href="/blog" className="transition hover:text-blue-500">Tips & Artikel</Link></li>
              <li><Link href="/member" className="transition hover:text-blue-500">Program Member</Link></li>
            </ul>
          </div>

          {/* Layanan */}
          <div>
            <p className="font-semibold text-gray-900">Layanan</p>
            <ul className="mt-4 space-y-2 text-sm text-gray-500">
              <li><Link href="/order-status" className="transition hover:text-blue-500">Cek Status Pesanan</Link></li>
              <li><Link href="/member/orders" className="transition hover:text-blue-500">Riwayat Pesanan</Link></li>
              <li>
                <a
                  href={`https://wa.me/${wa.replace("+", "")}`}
                  target="_blank"
                  rel="noreferrer"
                  className="transition hover:text-natalo-600"
                >
                  Hubungi Kami
                </a>
              </li>
              <li><Link href="/member/login" className="transition hover:text-blue-500">Login Member</Link></li>
            </ul>
          </div>

          {/* Info */}
          <div>
            <p className="font-semibold text-gray-900">Informasi</p>
            <ul className="mt-4 space-y-2 text-sm text-gray-500">
              <li>WhatsApp: {wa}</li>
            </ul>
            <OperatingHours className="mt-3 space-y-2 text-sm text-gray-500" />
          </div>

          {/* Legal */}
          <div>
            <p className="font-semibold text-gray-900">Legal</p>
            <ul className="mt-4 space-y-2 text-sm text-gray-500">
              <li><Link href="/cara-pemesanan" className="transition hover:text-natalo-600">Cara Pemesanan</Link></li>
              <li><Link href="/syarat-ketentuan" className="transition hover:text-natalo-600">Syarat & Ketentuan</Link></li>
              <li><Link href="/kebijakan-privasi" className="transition hover:text-natalo-600">Kebijakan Privasi</Link></li>
              <li><Link href="/kebijakan-pengembalian" className="transition hover:text-natalo-600">Pengembalian & Refund</Link></li>
            </ul>
          </div>
        </div>

        <div className="mt-10 border-t border-gray-200 pt-6 text-center text-xs text-gray-400">
          © {new Date().getFullYear()} {brand}. All rights reserved.
        </div>
      </div>
    </footer>
  );
}
