"use client";

import Link from "next/link";
import Image from "next/image";
import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { CartCount } from "./CartCount";
import { NotificationBell } from "./NotificationBell";
import { HomeSearchBar } from "@/components/home/HomeSearchBar";
import { bootstrapCartSync, switchToGuestCart } from "@/lib/cart";
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
  "/member",
  "/akun",
]);

// Halaman auth (login / daftar / OTP / lupa-reset password) — header dirender
// dalam variant minimal: back + title saja. Search/bell/profile/login button
// di-hide untuk fokus pada auth flow.
const AUTH_PATHS: Record<string, string> = {
  "/member/login": "Masuk",
  "/member/register": "Daftar Member",
  "/member/forgot-password": "Lupa Password",
  "/member/reset-password": "Reset Password",
};

function normalizePathname(pathname: string | null) {
  if (!pathname || pathname === "/") return "/";
  return pathname.replace(/\/+$/, "");
}

function isMainTabPath(pathname: string) {
  return MAIN_TAB_PATHS.has(pathname);
}

function isAccountArea(pathname: string) {
  // /member dan sub-page-nya (orders, profile, points, dll) + /akun/* (settings
  // sub-pages) dianggap "account section" — profile chip di header disembunyikan
  // karena user sudah berada di area akun.
  return pathname === "/member" || pathname.startsWith("/member/") || pathname.startsWith("/akun");
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
  const [member, setMember] = useState<MemberProfile | null>(null);
  const pathname = usePathname();
  const currentPath = normalizePathname(pathname);
  const isHome = currentPath === "/";
  const isSearchPage = currentPath === "/search";
  const isProductDetail = /^\/products\/[^/]+$/.test(currentPath);
  const isMainTab = isMainTabPath(currentPath);
  const authTitle = AUTH_PATHS[currentPath];
  const isAuthPage = authTitle !== undefined;
  const isInAccountArea = isAccountArea(currentPath);
  const isLoggedIn = Boolean(member?.name);
  // Contextual flags — header dirender berbeda berdasar auth state + page type.
  // Search icon kecil di header sengaja dihilangkan total: search hanya via
  // search bar besar di /, /products. Lebih clean + native (HIG).
  const showBell = isLoggedIn && !isAuthPage;
  const showProfileChip = isLoggedIn && !isAuthPage && !isInAccountArea;
  const showLoginButton = !isLoggedIn && !isAuthPage;
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

  if (isSearchPage) return null;

  // Auth pages — render minimal header: back button + title saja. Bottom nav,
  // bell, profile, login button semua di-hide untuk fokus ke flow auth.
  if (isAuthPage) {
    return (
      <header className="nat-site-header z-50 bg-white shadow-sm md:sticky">
        <div className="nat-header-inner nat-safe-x mx-auto flex max-w-6xl items-center justify-between gap-2 py-1.5 md:py-3">
          <button
            type="button"
            onClick={handleBack}
            className="-ml-1 flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-gray-800 active:bg-gray-100"
            aria-label="Kembali ke halaman sebelumnya"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} className="h-5 w-5">
              <path d="M15 18l-6-6 6-6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
          <h1 className="flex-1 truncate text-center text-base font-bold text-gray-900">
            {authTitle}
          </h1>
          {/* Spacer simetris untuk visual balance dengan back button di kiri. */}
          <span aria-hidden className="h-10 w-10 shrink-0" />
        </div>
      </header>
    );
  }

  return (
    <header
      className={
        isProductDetail
          ? "product-detail-header nat-site-header bg-white md:sticky md:z-50 md:shadow-sm"
          : isHome
          ? "nat-site-header mobile-sticky-header md:sticky"
          : "nat-site-header z-50 bg-white shadow-sm md:sticky"
      }
    >
      {isProductDetail && (
        <div className="product-detail-header-inner nat-safe-x mx-auto flex max-w-6xl items-center justify-between gap-1.5 md:hidden">
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

        {/* Right actions — contextual:
            - Guest: tombol "Masuk" saja (no bell, no profile chip).
            - Member: bell + profile chip (kecuali di /member & /akun area
              dimana user sudah di akun → chip disembunyikan).
            - Search icon kecil dihapus total: pakai search bar besar di
              / dan /products saja (lebih native, lebih mudah tap di mobile). */}
        <div className="flex shrink-0 items-center gap-1 xs:gap-1.5 md:gap-2">
          {/* Notifikasi — hanya untuk logged-in user. Guest tidak punya
              konteks notif (order, voucher, point) jadi bell dihide. */}
          {showBell && <NotificationBell />}

          {/* Cart: desktop header only; mobile already has bottom navigation. */}
          <div className="hidden h-10 w-10 items-center justify-center rounded-full text-gray-600 transition hover:bg-gray-100 md:flex [&_span.hidden]:!hidden [&_svg]:!h-5 [&_svg]:!w-5">
            <CartCount />
          </div>

          {/* Member avatar — bulat, inisial user. Tap → Member Center (/member).
              Tap area 44x44 (h-11 w-11) sesuai HIG; visual circle 40px (h-10 w-10).
              Disembunyikan saat user sudah di /member atau /akun (tidak perlu
              shortcut ke tempat yang sedang dibuka). */}
          {showProfileChip && member?.name && (
            <Link
              href="/member"
              aria-label={`Member Center — ${member.name}`}
              className="flex h-11 w-11 items-center justify-center rounded-full text-blue-700 transition active:scale-95"
            >
              <span className="flex h-10 w-10 items-center justify-center rounded-full bg-blue-500 text-sm font-black text-white shadow-sm transition hover:bg-blue-600">
                {member.name.charAt(0).toUpperCase()}
              </span>
            </Link>
          )}

          {showLoginButton && (
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
