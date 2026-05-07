"use client";

import Link from "next/link";
import { useState, useEffect } from "react";
import { usePathname } from "next/navigation";
import { CartCount } from "./CartCount";
import { WishlistCount } from "./WishlistButton";
import { bootstrapCartSync } from "@/lib/cart";

const NAV_LINKS = [
  { href: "/", label: "Beranda" },
  { href: "/products", label: "Produk" },
  { href: "/tentang-kami", label: "Tentang Kami" },
  { href: "/member", label: "Member" },
];

type MemberProfile = {
  name?: string;
  email?: string | null;
  phone?: string | null;
};

export function Header() {
  const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Pet Shop";
  const [open, setOpen] = useState(false);
  const [member, setMember] = useState<MemberProfile | null>(null);
  const pathname = usePathname();

  useEffect(() => {
    let active = true;

    fetch("/api/auth/me", { cache: "no-store" })
      .then((res) => res.json())
      .then((data: MemberProfile) => {
        if (active) {
          setMember(data.name ? data : null);
          // Sync cart dari server kalau user login (multi-device support)
          if (data.name) bootstrapCartSync();
        }
      })
      .catch(() => {
        if (active) setMember(null);
      });

    return () => {
      active = false;
    };
  }, []);

  // Close on route change
  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  // Lock scroll when menu open
  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => { document.body.style.overflow = ""; };
  }, [open]);

  return (
    <header className="sticky top-0 z-50 bg-white shadow-sm">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2">
          <span className="text-2xl">🐾</span>
          <span className="font-bold text-gray-900">{brand}</span>
        </Link>

        {/* Desktop nav */}
        <nav className="hidden items-center gap-8 text-sm font-medium text-gray-700 md:flex">
          {NAV_LINKS.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className={`transition hover:text-orange-500 ${pathname === link.href ? "text-orange-500 font-semibold" : ""}`}
            >
              {link.href === "/member" && member?.name ? member.name : link.label}
            </Link>
          ))}
        </nav>

        {/* Right actions */}
        <div className="flex items-center gap-3">
          <Link href="/wishlist" className="relative flex h-10 w-10 items-center justify-center rounded-full text-gray-600 transition hover:bg-gray-100" aria-label="Wishlist">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} className="h-5 w-5">
              <path strokeLinecap="round" strokeLinejoin="round" d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12Z" />
            </svg>
            <WishlistCount />
          </Link>
          <CartCount />
          {member?.name ? (
            <Link
              href="/member"
              aria-label={`Akun ${member.name}`}
              title={member.name}
              className="hidden h-10 w-10 items-center justify-center rounded-full border border-orange-100 bg-orange-50 text-orange-600 transition hover:border-orange-200 hover:bg-orange-100 md:inline-flex"
            >
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={1.8}
                className="h-5 w-5"
                aria-hidden="true"
              >
                <path strokeLinecap="round" strokeLinejoin="round" d="M20 21a8 8 0 0 0-16 0" />
                <circle cx="12" cy="7" r="4" />
              </svg>
            </Link>
          ) : (
            <Link
              href="/member"
              className="hidden rounded-full bg-orange-500 px-5 py-2 text-sm font-semibold text-white transition hover:bg-orange-600 md:inline-flex"
            >
              Masuk
            </Link>
          )}
          {/* Mobile hamburger */}
          <button
            onClick={() => setOpen((v) => !v)}
            className="flex h-11 w-11 items-center justify-center rounded-full text-gray-700 transition hover:bg-gray-100 md:hidden"
            aria-label={open ? "Tutup menu" : "Buka menu"}
          >
            {open ? (
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5">
                <line x1="18" y1="6" x2="6" y2="18" />
                <line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            ) : (
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5">
                <line x1="3" y1="6" x2="21" y2="6" />
                <line x1="3" y1="12" x2="21" y2="12" />
                <line x1="3" y1="18" x2="21" y2="18" />
              </svg>
            )}
          </button>
        </div>
      </div>

      {/* Mobile dropdown menu */}
      {open && (
        <div className="border-t border-gray-100 bg-white md:hidden">
          <nav className="mx-auto max-w-6xl px-4 py-3 space-y-1">
            {NAV_LINKS.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className={`flex items-center rounded-xl px-4 py-3 text-sm font-medium transition ${
                  pathname === link.href
                    ? "bg-orange-50 text-orange-500 font-semibold"
                    : "text-gray-700 hover:bg-gray-50"
                }`}
              >
                {link.href === "/member" && member?.name ? member.name : link.label}
              </Link>
            ))}
            {!member?.name && (
              <Link
                href="/member"
                className="mt-2 flex w-full items-center justify-center rounded-full bg-orange-500 py-3 text-sm font-bold text-white transition hover:bg-orange-600"
              >
                Masuk / Daftar Member
              </Link>
            )}
          </nav>
        </div>
      )}
    </header>
  );
}
