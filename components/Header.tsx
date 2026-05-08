"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { WishlistCount } from "./WishlistButton";
import { bootstrapCartSync, clearLocalCart } from "@/lib/cart";

const NAV_LINKS = [
  { href: "/", label: "Beranda" },
  { href: "/products", label: "Produk" },
  { href: "/tentang-kami", label: "Tentang Kami" },
];

type MemberProfile = {
  name?: string;
  email?: string | null;
  phone?: string | null;
};

export function Header() {
  const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Pet Shop";
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [memberMenuOpen, setMemberMenuOpen] = useState(false);
  const [member, setMember] = useState<MemberProfile | null>(null);
  const pathname = usePathname();
  const memberMenuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let active = true;

    fetch("/api/auth/me", { cache: "no-store" })
      .then((res) => res.json())
      .then((data: MemberProfile) => {
        if (active) {
          setMember(data.name ? data : null);
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
    setMemberMenuOpen(false);
  }, [pathname]);

  // Lock scroll when hamburger menu open
  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [open]);

  // Click outside to close member dropdown
  useEffect(() => {
    function onClick(e: MouseEvent) {
      if (!memberMenuOpen) return;
      if (memberMenuRef.current && !memberMenuRef.current.contains(e.target as Node)) {
        setMemberMenuOpen(false);
      }
    }
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, [memberMenuOpen]);

  async function handleLogout() {
    setMemberMenuOpen(false);
    clearLocalCart();
    await fetch("/api/auth/logout", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ scope: "CUSTOMER" }),
    }).catch(() => {});
    clearLocalCart();
    setMember(null);
    router.push("/");
    router.refresh();
  }

  return (
    <header className="sticky top-0 z-50 bg-white shadow-sm">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-2 px-4 py-3 md:py-4">
        {/* Logo */}
        <Link href="/" aria-label={brand} className="flex items-center shrink-0">
          <Image
            src="/logo.png"
            alt={brand}
            width={480}
            height={150}
            priority
            className="h-9 w-auto md:h-11"
          />
        </Link>

        {/* Desktop nav */}
        <nav className="hidden items-center gap-8 text-sm font-medium text-gray-700 md:flex">
          {NAV_LINKS.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className={`transition hover:text-orange-500 ${
                pathname === link.href ? "font-semibold text-orange-500" : ""
              }`}
            >
              {link.label}
            </Link>
          ))}
        </nav>

        {/* Right actions */}
        <div className="flex items-center gap-1.5 md:gap-2">
          {/* Wishlist */}
          <Link
            href="/wishlist"
            className="relative flex h-10 w-10 items-center justify-center rounded-full text-gray-600 transition hover:bg-gray-100"
            aria-label="Wishlist"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth={1.8}
              className="h-5 w-5"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12Z"
              />
            </svg>
            <WishlistCount />
          </Link>

          {/* Member area */}
          {member?.name ? (
            <div className="relative" ref={memberMenuRef}>
              <button
                type="button"
                onClick={() => setMemberMenuOpen((v) => !v)}
                className="flex h-10 items-center gap-2 rounded-full border border-orange-100 bg-orange-50 px-2 text-sm font-semibold text-orange-700 transition hover:border-orange-200 hover:bg-orange-100 md:px-3"
                aria-expanded={memberMenuOpen}
                aria-haspopup="menu"
              >
                <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-orange-500 text-xs font-black text-white">
                  {member.name.charAt(0).toUpperCase()}
                </span>
                <span className="hidden max-w-[100px] truncate xs:inline">
                  {member.name.split(" ")[0]}
                </span>
                <svg
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth={2.5}
                  className={`h-3 w-3 transition-transform ${memberMenuOpen ? "rotate-180" : ""}`}
                >
                  <polyline points="6 9 12 15 18 9" />
                </svg>
              </button>

              {memberMenuOpen && (
                <div
                  role="menu"
                  className="absolute right-0 top-full z-50 mt-2 w-56 overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-lg"
                >
                  <div className="border-b border-gray-100 px-4 py-3">
                    <p className="truncate text-sm font-bold text-gray-900">
                      {member.name}
                    </p>
                    {member.email && (
                      <p className="mt-0.5 truncate text-xs text-gray-500">
                        {member.email}
                      </p>
                    )}
                  </div>
                  <ul className="py-1.5">
                    {[
                      { href: "/member/profile", icon: "👤", label: "Profil Saya" },
                      { href: "/member/orders", icon: "📦", label: "Riwayat Pesanan" },
                      { href: "/wishlist", icon: "❤️", label: "Wishlist" },
                      { href: "/member/points", icon: "⭐", label: "Loyalty Point" },
                      { href: "/order-status", icon: "📍", label: "Lacak Pesanan" },
                    ].map((item) => (
                      <li key={item.href}>
                        <Link
                          href={item.href}
                          onClick={() => setMemberMenuOpen(false)}
                          className="flex items-center gap-3 px-4 py-2.5 text-sm text-gray-700 transition hover:bg-orange-50 hover:text-orange-600"
                        >
                          <span className="text-base">{item.icon}</span>
                          <span>{item.label}</span>
                        </Link>
                      </li>
                    ))}
                  </ul>
                  <div className="border-t border-gray-100">
                    <button
                      type="button"
                      onClick={handleLogout}
                      className="flex w-full items-center gap-3 px-4 py-3 text-sm font-semibold text-red-500 transition hover:bg-red-50"
                    >
                      <span className="text-base">🚪</span>
                      <span>Keluar</span>
                    </button>
                  </div>
                </div>
              )}
            </div>
          ) : (
            <Link
              href="/member/login"
              className="rounded-full bg-orange-500 px-4 py-2 text-xs font-bold text-white transition hover:bg-orange-600 md:px-5 md:text-sm"
            >
              Masuk
            </Link>
          )}

          {/* Mobile hamburger */}
          <button
            onClick={() => setOpen((v) => !v)}
            className="flex h-10 w-10 items-center justify-center rounded-full text-gray-700 transition hover:bg-gray-100 md:hidden"
            aria-label={open ? "Tutup menu" : "Buka menu"}
          >
            {open ? (
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={2}
                className="h-5 w-5"
              >
                <line x1="18" y1="6" x2="6" y2="18" />
                <line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            ) : (
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={2}
                className="h-5 w-5"
              >
                <line x1="3" y1="6" x2="21" y2="6" />
                <line x1="3" y1="12" x2="21" y2="12" />
                <line x1="3" y1="18" x2="21" y2="18" />
              </svg>
            )}
          </button>
        </div>
      </div>

      {/* Mobile dropdown — site navigation only (member actions di dropdown avatar) */}
      {open && (
        <div className="border-t border-gray-100 bg-white md:hidden">
          <nav className="mx-auto max-w-6xl space-y-1 px-4 py-3">
            {NAV_LINKS.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className={`flex items-center rounded-xl px-4 py-3 text-sm font-medium transition ${
                  pathname === link.href
                    ? "bg-orange-50 font-semibold text-orange-500"
                    : "text-gray-700 hover:bg-gray-50"
                }`}
              >
                {link.label}
              </Link>
            ))}
            {!member?.name && (
              <Link
                href="/member/register"
                className="mt-2 flex w-full items-center justify-center rounded-full border border-orange-300 py-3 text-sm font-bold text-orange-600 transition hover:bg-orange-50"
              >
                Daftar Member Baru
              </Link>
            )}
          </nav>
        </div>
      )}
    </header>
  );
}
