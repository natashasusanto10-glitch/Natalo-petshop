"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import type { IconType } from "react-icons";
import {
  IoGrid,
  IoGridOutline,
  IoHome,
  IoHomeOutline,
  IoPerson,
  IoPersonOutline,
  IoPlayCircle,
  IoPlayCircleOutline,
} from "react-icons/io5";
import { bootstrapCartSync } from "@/lib/cart";
import { prefetchCategories } from "@/lib/client-performance";
import { hapticTap } from "@/lib/native/haptics";
import { shouldHideBottomNav } from "@/lib/navigation";

type NavIconType = IconType;

const ITEMS: {
  href: string;
  label: string;
  icon: NavIconType;
  activeIcon: NavIconType;
}[] = [
  { href: "/", label: "Beranda", icon: IoHomeOutline, activeIcon: IoHome },
  { href: "/products", label: "Produk", icon: IoGridOutline, activeIcon: IoGrid },
  { href: "/feed", label: "Feed", icon: IoPlayCircleOutline, activeIcon: IoPlayCircle },
  { href: "/member", label: "Akun", icon: IoPersonOutline, activeIcon: IoPerson },
];

function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  if (href === "/products") {
    return pathname === "/products" || pathname.startsWith("/products/") || pathname === "/kategori" || pathname === "/produk";
  }
  return pathname === href || pathname.startsWith(`${href}/`);
}

function NavIcon({ icon, active }: { icon: NavIconType; active: boolean }) {
  const Icon = icon;
  return (
    <span
      className={`flex h-6 w-6 items-center justify-center transition-transform duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${
        active ? "-translate-y-0.5 scale-110" : ""
      }`}
    >
      <Icon aria-hidden className="h-6 w-6" />
    </span>
  );
}

export function BottomNavigation() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const router = useRouter();
  const [optimisticHref, setOptimisticHref] = useState<string | null>(null);

  useEffect(() => {
    setOptimisticHref(null);
  }, [pathname]);

  useEffect(() => {
    const id = window.setTimeout(() => {
      router.prefetch("/");
      router.prefetch("/products");
      router.prefetch("/feed");
      router.prefetch("/member");
      prefetchCategories();
      void bootstrapCartSync();
    }, 800);

    return () => window.clearTimeout(id);
  }, [router]);

  const activeIndex = useMemo(() => {
    const i = ITEMS.findIndex((item) =>
      optimisticHref ? item.href === optimisticHref : isActive(pathname, item.href),
    );
    return i === -1 ? 0 : i;
  }, [pathname, optimisticHref]);

  const hideNav = shouldHideBottomNav(pathname) || (pathname === "/products" && Boolean(searchParams.get("q")?.trim()));

  // Sync body data attribute supaya CSS bisa adjust .nat-main-shell
  // padding-bottom (tanpa space kosong saat nav hidden). Pakai useEffect
  // hanya untuk side-effect ini — render utama tetap kontrolled lewat
  // conditional return di bawah.
  useEffect(() => {
    if (typeof document === "undefined") return;
    if (hideNav) {
      document.body.dataset.bottomNav = "hidden";
    } else {
      delete document.body.dataset.bottomNav;
    }
    return () => {
      if (typeof document !== "undefined") {
        delete document.body.dataset.bottomNav;
      }
    };
  }, [hideNav]);

  if (hideNav) return null;

  return (
    <nav className="bottom-nav nat-bottom-nav md:hidden" aria-label="Navigasi utama">
      {/* Full-width backdrop edge-fade — gradient putih dari transparent di
          atas → solid putih di bawah. Cover ENTIRE nav zone (pill height +
          margin + safe-area), bukan cuma safe-area. Tujuan: content scroll
          fade lembut ke putih sebelum hilang di belakang pill, side strips
          (di kiri/kanan pill mx-3) tidak lagi expose product card. Pill
          tetap floating di atas via z-stacking + shadow. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 bottom-0 h-[calc(env(safe-area-inset-bottom)+100px)] bg-gradient-to-t from-white from-72% to-white/0"
      />
      <div className="pointer-events-auto relative mx-3 mb-2">
        <div className="bottom-nav-glass relative grid h-[60px] grid-cols-4 overflow-hidden rounded-full">
          <span
            aria-hidden
            className="pointer-events-none absolute left-0 top-1.5 bottom-1.5 w-1/4 rounded-full bg-natalo-50 transition-transform duration-[450ms] ease-[cubic-bezier(0.34,1.56,0.64,1)]"
            style={{ transform: `translateX(${activeIndex * 100}%)` }}
          />
          {ITEMS.map((item, i) => {
            const active = i === activeIndex;
            const Icon = active ? item.activeIcon : item.icon;
            return (
              <Link
                key={item.href}
                href={item.href}
                prefetch
                onClick={() => {
                  if (!active) hapticTap();
                  setOptimisticHref(item.href);
                }}
                onMouseEnter={() => router.prefetch(item.href)}
                onTouchStart={() => router.prefetch(item.href)}
                aria-current={active ? "page" : undefined}
                className={`relative z-[1] flex h-full flex-col items-center justify-center gap-1 px-1 text-[11px] leading-none transition-colors duration-200 active:opacity-90 ${
                  active ? "font-extrabold text-[#1E5FBF]" : "font-semibold text-[#9ca3af]"
                }`}
              >
                <span className="relative">
                  <NavIcon icon={Icon} active={active} />
                </span>
                <span>{item.label}</span>
              </Link>
            );
          })}
        </div>
      </div>
    </nav>
  );
}
