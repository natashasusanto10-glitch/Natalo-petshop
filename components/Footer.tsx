import Link from "next/link";

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
        <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
          {/* Brand */}
          <div>
            <Link href="/" className="flex items-center gap-2">
              <span className="text-xl">🐾</span>
              <span className="font-bold text-gray-900">{brand}</span>
            </Link>
            <p className="mt-3 text-sm leading-relaxed text-gray-500">
              Toko hewan peliharaan terpercaya. Produk berkualitas untuk sahabat berbulu kamu.
            </p>
            <div className="mt-4 flex gap-3">
              {[
                { label: "Facebook", href: "#", icon: "f" },
                { label: "Instagram", href: "#", icon: "ig" },
                { label: "WhatsApp", href: `https://wa.me/${wa.replace("+", "")}`, icon: "wa" },
              ].map((s) => (
                <a
                  key={s.label}
                  href={s.href}
                  target="_blank"
                  rel="noreferrer"
                  aria-label={s.label}
                  className="flex h-9 w-9 items-center justify-center rounded-full border border-gray-200 bg-white text-xs font-bold text-gray-600 transition hover:border-orange-500 hover:text-orange-500"
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
              <li><Link href="/products" className="transition hover:text-orange-500">Semua Produk</Link></li>
              <li><Link href="/wishlist" className="transition hover:text-orange-500">Wishlist</Link></li>
              <li><Link href="/blog" className="transition hover:text-orange-500">Tips & Artikel</Link></li>
              <li><Link href="/member" className="transition hover:text-orange-500">Program Member</Link></li>
            </ul>
          </div>

          {/* Layanan */}
          <div>
            <p className="font-semibold text-gray-900">Layanan</p>
            <ul className="mt-4 space-y-2 text-sm text-gray-500">
              <li><Link href="/order-status" className="transition hover:text-orange-500">Cek Status Pesanan</Link></li>
              <li><Link href="/member/orders" className="transition hover:text-orange-500">Riwayat Pesanan</Link></li>
              <li>
                <a
                  href={`https://wa.me/${wa.replace("+", "")}`}
                  target="_blank"
                  rel="noreferrer"
                  className="transition hover:text-orange-500"
                >
                  Hubungi Kami
                </a>
              </li>
              <li><Link href="/member/login" className="transition hover:text-orange-500">Login Member</Link></li>
            </ul>
          </div>

          {/* Info */}
          <div>
            <p className="font-semibold text-gray-900">Informasi</p>
            <ul className="mt-4 space-y-2 text-sm text-gray-500">
              <li>WhatsApp: {wa}</li>
              <li>Senin – Sabtu</li>
              <li>08.00 – 20.00 WIB</li>
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
