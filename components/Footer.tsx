import Link from "next/link";
import { OperatingHours } from "@/components/OperatingHours";

function InstagramIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-4 w-4" aria-hidden="true">
      <rect x="2" y="2" width="20" height="20" rx="5" />
      <path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z" />
      <line x1="17.5" y1="6.5" x2="17.51" y2="6.5" />
    </svg>
  );
}

function WhatsAppIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" className="h-4 w-4" aria-hidden="true">
      <path d="M20.52 3.48A12 12 0 0 0 3.5 20.36L2 22l1.69-1.55A12 12 0 1 0 20.52 3.48Zm-8.4 18a10 10 0 0 1-5.1-1.4l-.36-.21-3.06.86.82-3-.24-.38a10 10 0 1 1 7.94 4.13Zm5.5-7.5c-.3-.15-1.78-.88-2-1s-.5-.15-.7.15-.82 1-1 1.2-.36.22-.66.07a8.2 8.2 0 0 1-2.4-1.48 9.05 9.05 0 0 1-1.66-2.07c-.17-.3 0-.46.13-.61s.3-.36.45-.54a2.1 2.1 0 0 0 .3-.5.55.55 0 0 0 0-.53c-.07-.15-.7-1.67-.95-2.28s-.5-.52-.7-.53h-.6a1.16 1.16 0 0 0-.83.39 3.5 3.5 0 0 0-1.1 2.6 6.07 6.07 0 0 0 1.27 3.23 13.92 13.92 0 0 0 5.34 4.7c.74.32 1.32.5 1.78.65a4.3 4.3 0 0 0 2 .12 3.24 3.24 0 0 0 2.13-1.5 2.65 2.65 0 0 0 .19-1.5c-.07-.13-.27-.2-.57-.35Z" />
    </svg>
  );
}

function TikTokIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" className="h-4 w-4" aria-hidden="true">
      <path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 0 1-2.88 2.5 2.89 2.89 0 0 1-2.89-2.89 2.89 2.89 0 0 1 2.89-2.89c.28 0 .54.04.79.1V9.01a6.33 6.33 0 0 0-.79-.05 6.34 6.34 0 0 0-6.34 6.34 6.34 6.34 0 0 0 6.34 6.34 6.34 6.34 0 0 0 6.33-6.34V8.69a8.18 8.18 0 0 0 4.78 1.52V6.76a4.85 4.85 0 0 1-1.01-.07Z" />
    </svg>
  );
}

function PawIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="h-5 w-5" aria-hidden="true">
      <path d="M8 20c-2 0-3-1.2-3-2.7 0-2.4 3.1-4.8 7-4.8s7 2.4 7 4.8c0 1.5-1 2.7-3 2.7-1.4 0-2.5-.8-4-.8s-2.6.8-4 .8Z" />
      <circle cx="6.5" cy="10" r="1.8" />
      <circle cx="10" cy="7" r="1.8" />
      <circle cx="14" cy="7" r="1.8" />
      <circle cx="17.5" cy="10" r="1.8" />
    </svg>
  );
}

export function Footer() {
  const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop";
  const wa = process.env.NEXT_PUBLIC_WA_NUMBER || process.env.NEXT_PUBLIC_WHATSAPP_NUMBER || "";
  const waHref = wa ? `https://wa.me/${wa.replace("+", "")}` : "#";

  const socialLinks = [
    { label: "Instagram", href: "https://www.instagram.com/natalopetshop/", icon: <InstagramIcon /> },
    { label: "WhatsApp", href: waHref, icon: <WhatsAppIcon /> },
    { label: "TikTok", href: "https://www.tiktok.com/@natalopetshop", icon: <TikTokIcon /> },
  ];

  return (
    <footer className="mt-12 border-t border-zinc-100 bg-zinc-50">
      <div className="mx-auto max-w-6xl px-4 py-8">
        <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-[1.4fr_0.8fr_0.8fr_1fr]">
          <div>
            <Link href="/" className="inline-flex items-center gap-2 text-sm font-black text-zinc-950">
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-natalo-100 text-natalo-700">
                <PawIcon />
              </span>
              {brand}
            </Link>
            <p className="mt-3 max-w-sm text-sm leading-relaxed text-zinc-600">
              Petshop dan aquarium store di Medan untuk kebutuhan kucing, anjing, ikan, burung, dan hewan peliharaan lainnya.
            </p>
            <div className="mt-4 flex gap-2">
              {socialLinks.map((item) => (
                <a
                  key={item.label}
                  href={item.href}
                  target="_blank"
                  rel="noreferrer"
                  aria-label={item.label}
                  className="flex h-9 w-9 items-center justify-center rounded-full border border-zinc-200 bg-white text-zinc-600 transition hover:border-natalo-500 hover:text-natalo-600"
                >
                  {item.icon}
                </a>
              ))}
            </div>
          </div>

          <div>
            <p className="text-sm font-black text-zinc-950">Toko</p>
            <ul className="mt-3 space-y-2 text-sm text-zinc-600">
              <li><Link href="/products" className="hover:text-natalo-600">Semua Produk</Link></li>
              <li><Link href="/kategori" className="hover:text-natalo-600">Kategori</Link></li>
              <li><Link href="/wishlist" className="hover:text-natalo-600">Wishlist</Link></li>
              <li><Link href="/member" className="hover:text-natalo-600">Program Member</Link></li>
            </ul>
          </div>

          <div>
            <p className="text-sm font-black text-zinc-950">Bantuan</p>
            <ul className="mt-3 space-y-2 text-sm text-zinc-600">
              <li><Link href="/order-status" className="hover:text-natalo-600">Cek Pesanan</Link></li>
              <li><Link href="/cara-pemesanan" className="hover:text-natalo-600">Cara Pemesanan</Link></li>
              <li><Link href="/member/orders" className="hover:text-natalo-600">Riwayat Pesanan</Link></li>
              <li><Link href="/kebijakan-pengembalian" className="hover:text-natalo-600">Pengembalian</Link></li>
            </ul>
          </div>

          <div>
            <p className="text-sm font-black text-zinc-950">Kontak Admin</p>
            <ul className="mt-3 space-y-2 text-sm text-zinc-600">
              {wa && (
                <li>
                  <a href={waHref} target="_blank" rel="noreferrer" className="font-bold text-natalo-700 hover:underline">
                    WhatsApp: {wa}
                  </a>
                </li>
              )}
              <li><Link href="/tentang-kami" className="hover:text-natalo-600">Tentang Natalo</Link></li>
              <li><Link href="/syarat-ketentuan" className="hover:text-natalo-600">Syarat & Ketentuan</Link></li>
              <li><Link href="/kebijakan-privasi" className="hover:text-natalo-600">Kebijakan Privasi</Link></li>
            </ul>
            <OperatingHours className="mt-3 space-y-1 text-xs text-zinc-500" />
          </div>
        </div>

        <div className="mt-7 flex flex-col gap-2 border-t border-zinc-200 pt-4 text-xs text-zinc-500 sm:flex-row sm:items-center sm:justify-between">
          <span>&copy; {new Date().getFullYear()} {brand}. All rights reserved.</span>
          <span>Original products. Fast response admin. Delivery support area Medan.</span>
        </div>
      </div>
    </footer>
  );
}
