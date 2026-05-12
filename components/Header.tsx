"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { CartCount } from "./CartCount";
import { NotificationBell } from "./NotificationBell";
import { HomeSearchBar } from "@/components/home/HomeSearchBar";
import { bootstrapCartSync, clearLocalCart, switchToGuestCart } from "@/lib/cart";
import { prefetchCategories } from "@/lib/client-performance";
import { shareContent } from "@/lib/share";
import { natToast } from "@/components/Toast";

const NAV_LINKS = [
  { href: "/", label: "Beranda" },
  { href: "/products", label: "Produk" },
  { href: "/tentang-kami", label: "Tentang Kami" },
];

// Halaman yang ada di BottomNavigation — gak perlu tombol back karena
// user bisa pindah via tab.
const MAIN_TAB_PATHS = new Set([
  "/",
  "/products",
  "/produk",
  "/kategori",
  "/cart",
  "/member",
  "/member/login",
  "/akun",
]);

function normalizePathname(pathname: string | null) {
  if (!pathname || pathname === "/") return "/";
  return pathname.replace(/\/+$/, "");
}

function isMainTabPath(pathname: string) {
  return MAIN_TAB_PATHS.has(pathname);
}

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
  const currentPath = normalizePathname(pathname);
  const memberMenuRef = useRef<HTMLDivElement>(null);
  const isHome = currentPath === "/";
  const isProductDetail = /^\/products\/[^/]+$/.test(currentPath);
  const isMainTab = isMainTabPath(currentPath);
  // Back button universal: tampil di mobile untuk semua halaman selain main tab
  // & product detail (yang punya header sendiri dengan back + search + share + cart).
  const showBackButton = Boolean(pathname) && !isMainTab && !isProductDetail;

  function handleBack() {
    // Fallback ke home kalau buka deep link langsung (no history) — biar back gak
    // exit out of app di iOS native (yang bikin pengalaman jelek).
    if (typeof window !== "undefined" && window.history.length > 1) {
      router.back();
    } else {
      router.push("/");
    }
  }

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
    // Listen pull-to-refresh — refetch member info & re-bootstrap cart sync
    window.addEventListener("app-refresh", loadMember);

    return () => {
      active = false;
      window.removeEventListener("auth-updated", loadMember);
      window.removeEventListener("app-refresh", loadMember);
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
    // Universal share via lib/share.ts:
    // 1. iOS native (.ipa) → UIActivityView dengan semua app installed
    //    (WhatsApp, Instagram, Mail, AirDrop, Notes, dll)
    // 2. Web modern → Web Share API
    // 3. Fallback → clipboard copy + toast feedback
    const result = await shareContent({
      title: document.title,
      text: `Cek produk ini di Natalo Petshop: ${document.title}`,
      url: window.location.href,
      dialogTitle: "Bagikan produk",
    });

    if (result.method === "clipboard") {
      natToast("Link disalin — paste ke chat / sosial media", { kind: "ok" });
    } else if (result.method === "failed") {
      natToast("Gagal membagikan — coba lagi", { kind: "err" });
    }
    // method "native" / "web-share" / "cancelled" — gak perlu toast
    // karena UI sheet Apple/browser sudah kasih feedback sendiri
  }

  return (
    <header
      className={
        isHome
          ? "nat-site-header mobile-sticky-header md:sticky"
          : "nat-site-header z-50 bg-white shadow-sm md:sticky"
      }
    >
      {isProductDetail && (
        <div className="nat-header-inner nat-safe-x mx-auto flex max-w-6xl items-center justify-between gap-1.5 py-1.5 md:hidden">
          <button
            type="button"
            onClick={handleBack}
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
      <div
        className={
          isHome
            ? "mobile-header-row mx-auto max-w-6xl gap-1.5 xs:gap-2"
            : "nat-header-inner nat-safe-x mx-auto flex max-w-6xl items-center justify-between gap-1.5 py-1.5 xs:gap-2 md:py-3"
        }
      >
        {/* Back button — hanya tampil di mobile untuk halaman non-main-tab.
            Memberikan fallback navigasi yang jelas selain swipe gesture iOS. */}
        {showBackButton && (
          <button
            type="button"
            onClick={handleBack}
            className="-ml-1 flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-gray-700 active:bg-gray-100 md:hidden"
            aria-label="Kembali ke halaman sebelumnya"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth={2.2}
              className="h-5 w-5"
            >
              <path d="M15 18l-6-6 6-6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
        )}
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
                currentPath === link.href ? "font-semibold text-blue-500" : ""
              }`}
            >
              {link.label}
            </Link>
          ))}
        </nav>

        {/* Right actions */}
        <div className="flex shrink-0 items-center gap-1 xs:gap-1.5 md:gap-2">
          {/* Search */}
          <Link
            href="/search"
            className="flex h-9 w-9 items-center justify-center rounded-full text-gray-600 transition hover:bg-gray-100 xs:h-10 xs:w-10"
            aria-label="Cari produk"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.9} className="h-5 w-5">
              <circle cx="11" cy="11" r="7" />
              <path d="m20 20-3.5-3.5" strokeLinecap="round" />
            </svg>
          </Link>

          {/* Notifikasi — ganti dari Wishlist. Wishlist tetap diakses dari
              heart di kartu produk + dropdown menu member di bawah. */}
          <NotificationBell />

          {/* Cart: desktop header only; mobile already has bottom navigation. */}
          <div className="hidden h-10 w-10 items-center justify-center rounded-full text-gray-600 transition hover:bg-gray-100 md:flex [&_span.hidden]:!hidden [&_svg]:!h-5 [&_svg]:!w-5">
            <CartCount />
          </div>

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
                <span className="max-w-[82px] truncate xs:max-w-[100px]">
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
              href="/member/login?redirect=%2F"
              className="rounded-full bg-blue-500 px-3 py-2 text-xs font-bold text-white transition hover:bg-blue-600 xs:px-4 md:px-5 md:text-sm"
            >
              Masuk
            </Link>
          )}

        </div>
      </div>
      {isHome && <HomeSearchBar />}
      </div>
    </header>
  );
}
