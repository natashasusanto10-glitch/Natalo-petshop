"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { WishlistCount } from "./WishlistButton";
import { CartCount } from "./CartCount";
import { bootstrapCartSync, clearLocalCart, switchToGuestCart } from "@/lib/cart";
import { prefetchCategories } from "@/lib/client-performance";

const NAV_LINKS = [
  { href: "/", label: "Beranda" },
  { href: "/products", label: "Produk" },
  { href: "/tentang-kami", label: "Tentang Kami" },
];

type MemberProfile = {
  id?: string;
  name?: string;
  email?: string | null;
  phone?: string | null;
};

export function Header() {
  const brand = process.env.NEXT_PUBLIC_BRAND_NAME || "Pet Shop";
  const router = useRouter();
  const [memberMenuOpen, setMemberMenuOpen] = useState(false);
  const [member, setMember] = useState<MemberProfile | null>(null);
  const pathname = usePathname();
  const memberMenuRef = useRef<HTMLDivElement>(null);
  const isProductDetail = /^\/products\/[^/]+$/.test(pathname ?? "");

  useEffect(() => {
    let active = true;

    async function loadMember() {
      fetch("/api/auth/me", { cache: "no-store" })
      .then((res) => res.json())
      .then((data: MemberProfile) => {
        if (active) {
          setMember(data.name ? data : null);
          if (data.name) bootstrapCartSync();
          else switchToGuestCart();
        }
      })
      .catch(() => {
        if (active) {
          setMember(null);
          switchToGuestCart();
        }
      });
    }

    loadMember();
    window.addEventListener("auth-updated", loadMember);

    return () => {
      active = false;
      window.removeEventListener("auth-updated", loadMember);
    };
  }, []);

  useEffect(() => {
    const id = window.setTimeout(() => {
      router.prefetch("/products");
      router.prefetch("/cart");
      router.prefetch("/member");
      prefetchCategories();
    }, 1000);

    return () => window.clearTimeout(id);
  }, [router]);

  // Close on route change
  useEffect(() => {
    setMemberMenuOpen(false);
  }, [pathname]);

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

  async function handleShare() {
    const shareData = { title: document.title, url: window.location.href };
    if (navigator.share) {
      await navigator.share(shareData).catch(() => {});
      return;
    }
    await navigator.clipboard?.writeText(window.location.href).catch(() => {});
  }

  return (
    <header className="nat-site-header z-50 bg-white shadow-sm md:sticky">
      {isProductDetail && (
        <div className="nat-header-inner nat-safe-x mx-auto flex max-w-6xl items-center justify-between gap-1.5 py-1.5 md:hidden">
          <button
            type="button"
            onClick={() => router.back()}
            className="flex h-10 w-10 items-center justify-center rounded-full text-gray-800 active:bg-gray-100"
            aria-label="Kembali"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} className="h-5 w-5">
              <path d="M15 18l-6-6 6-6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>

          <div className="flex items-center gap-1">
            <Link
              href="/search"
              className="flex h-10 w-10 items-center justify-center rounded-full text-gray-700 active:bg-gray-100"
              aria-label="Cari produk"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5">
                <circle cx="11" cy="11" r="7" />
                <path d="m20 20-3.5-3.5" strokeLinecap="round" />
              </svg>
            </Link>
            <button
              type="button"
              onClick={handleShare}
              className="flex h-10 w-10 items-center justify-center rounded-full text-gray-700 active:bg-gray-100"
              aria-label="Bagikan produk"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5">
                <circle cx="18" cy="5" r="3" />
                <circle cx="6" cy="12" r="3" />
                <circle cx="18" cy="19" r="3" />
                <path d="M8.6 10.6 15.4 6.4M8.6 13.4l6.8 4.2" strokeLinecap="round" />
              </svg>
            </button>
            <div className="flex h-10 w-10 items-center justify-center rounded-full text-gray-700 active:bg-gray-100 [&_span.hidden]:hidden [&_svg]:!h-5 [&_svg]:!w-5">
              <CartCount />
            </div>
          </div>
        </div>
      )}
      <div className={isProductDetail ? "hidden md:block" : ""}>
      <div className="nat-header-inner nat-safe-x mx-auto flex max-w-6xl items-center justify-between gap-1.5 py-1.5 xs:gap-2 md:py-3">
        {/* Logo */}
        <Link href="/" aria-label={brand} className="flex min-w-0 shrink-0 items-center">
          <Image
            src="/logo.png"
            alt={brand}
            width={600}
            height={196}
            priority
            sizes="(max-width: 360px) 128px, (max-width: 768px) 150px, 180px"
            className="h-9 w-auto max-w-[128px] xs:h-10 xs:max-w-[150px] md:h-12 md:max-w-none"
          />
        </Link>

        {/* Desktop nav */}
        <nav className="hidden items-center gap-8 text-sm font-medium text-gray-700 md:flex">
          {NAV_LINKS.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className={`transition hover:text-blue-500 ${
                pathname === link.href ? "font-semibold text-blue-500" : ""
              }`}
            >
              {link.label}
            </Link>
          ))}
        </nav>

        {/* Right actions */}
        <div className="flex shrink-0 items-center gap-1 xs:gap-1.5 md:gap-2">
          {/* Wishlist */}
          <Link
            href="/wishlist"
            className="relative hidden h-9 w-9 items-center justify-center rounded-full text-gray-600 transition hover:bg-gray-100 xs:h-10 xs:w-10 md:flex"
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
                className="flex h-9 items-center gap-1.5 rounded-full border border-blue-100 bg-blue-50 px-1.5 text-sm font-semibold text-blue-700 transition hover:border-blue-200 hover:bg-blue-100 xs:h-10 xs:gap-2 xs:px-2 md:px-3"
                aria-expanded={memberMenuOpen}
                aria-haspopup="menu"
              >
                <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-blue-500 text-xs font-black text-white">
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
                          className="flex items-center gap-3 px-4 py-2.5 text-sm text-gray-700 transition hover:bg-blue-50 hover:text-blue-600"
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
              className="rounded-full bg-blue-500 px-3 py-2 text-xs font-bold text-white transition hover:bg-blue-600 xs:px-4 md:px-5 md:text-sm"
            >
              Masuk
            </Link>
          )}

        </div>
      </div>
      </div>
    </header>
  );
}
