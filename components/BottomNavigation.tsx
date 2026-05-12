"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { bootstrapCartSync, loadCart } from "@/lib/cart";
import { prefetchCategories } from "@/lib/client-performance";
import { hapticTap } from "@/lib/native/haptics";

type NavIconName = "home" | "catalog" | "bag" | "person";

const ITEMS: { href: string; label: string; icon: NavIconName }[] = [
  { href: "/", label: "Beranda", icon: "home" },
  { href: "/products", label: "Produk", icon: "catalog" },
  { href: "/cart", label: "Keranjang", icon: "bag" },
  { href: "/member", label: "Akun", icon: "person" },
];

function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  if (href === "/products") {
    return pathname === "/products" || pathname.startsWith("/products/") || pathname === "/kategori" || pathname === "/produk";
  }
  return pathname === href || pathname.startsWith(`${href}/`);
}

function NavIcon({ name, active }: { name: NavIconName; active: boolean }) {
  const paths: Record<NavIconName, ReactNode> = {
    home: (
      <>
        <path
          d="M5 14 L16 5 L27 14 V25 a2 2 0 0 1-2 2 H7 a2 2 0 0 1-2-2 Z"
          fill={active ? "#DBEAFE" : "transparent"}
        />
        <path d="M5 14 L16 5 L27 14 V25 a2 2 0 0 1-2 2 H7 a2 2 0 0 1-2-2 Z" />
        <ellipse cx="13" cy="18.5" rx="1.4" ry="1.8" fill="currentColor" stroke="none" />
        <ellipse cx="19" cy="18.5" rx="1.4" ry="1.8" fill="currentColor" stroke="none" />
        <ellipse cx="11" cy="22" rx="1.2" ry="1.5" fill="currentColor" stroke="none" />
        <ellipse cx="21" cy="22" rx="1.2" ry="1.5" fill="currentColor" stroke="none" />
        <ellipse cx="16" cy="24" rx="2.6" ry="2" fill="currentColor" stroke="none" />
      </>
    ),
    catalog: (
      <>
        <path d="M7 7.5 H25 a2 2 0 0 1 2 2 V24.5 a2 2 0 0 1-2 2 H7 a2 2 0 0 1-2-2 V9.5 a2 2 0 0 1 2-2 Z" />
        <path d="M9 13 H23" />
        <path d="M9 18 H23" />
        <path d="M13.5 7.5 V26.5" />
        <path d="M19 7.5 V26.5" />
        <path d="M10.5 5.5 H21.5" />
      </>
    ),
    bag: (
      <>
        <path d="M11 11 V9 a5 5 0 0 1 10 0 V11" />
        <path d="M7 11 H25 L23.5 26 a2 2 0 0 1-2 1.8 H10.5 a2 2 0 0 1-2-1.8 Z" />
        <ellipse cx="14" cy="18" rx="1" ry="1.3" fill="currentColor" stroke="none" />
        <ellipse cx="18" cy="18" rx="1" ry="1.3" fill="currentColor" stroke="none" />
        <ellipse cx="16" cy="21" rx="2" ry="1.6" fill="currentColor" stroke="none" />
      </>
    ),
    person: (
      <>
        <circle cx="16" cy="11" r="5" />
        <path d="M5 27 c1.5-5.5 6-8 11-8 s9.5 2.5 11 8" />
      </>
    ),
  };

  return (
    <span
      className={`flex h-6 w-6 items-center justify-center transition-transform duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${
        active ? "-translate-y-0.5 scale-110" : ""
      }`}
    >
      <svg
        aria-hidden="true"
        viewBox="0 0 32 32"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="h-6 w-6"
      >
        {paths[name]}
      </svg>
    </span>
  );
}

export function BottomNavigation() {
  const pathname = usePathname();
  const router = useRouter();
  const [cartCount, setCartCount] = useState(0);
  const [optimisticHref, setOptimisticHref] = useState<string | null>(null);

  useEffect(() => {
    function syncCart() {
      const items = loadCart();
      setCartCount(items.reduce((sum, item) => sum + Number(item.quantity || 0), 0));
    }

    function onStorage(e: StorageEvent) {
      if (e.key?.startsWith("cart")) syncCart();
    }
    syncCart();
    window.addEventListener("cart-updated", syncCart);
    window.addEventListener("storage", onStorage);
    return () => {
      window.removeEventListener("cart-updated", syncCart);
      window.removeEventListener("storage", onStorage);
    };
  }, []);

  useEffect(() => {
    setOptimisticHref(null);
  }, [pathname]);

  useEffect(() => {
    const id = window.setTimeout(() => {
      router.prefetch("/");
      router.prefetch("/products");
      router.prefetch("/cart");
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

  if (pathname === "/checkout" || pathname?.startsWith("/checkout/")) return null;

  return (
    <nav className="bottom-nav nat-bottom-nav md:hidden" aria-label="Navigasi utama">
      {/* Safe-area shield — gradient putih solid di bawah pill supaya content
          yang scroll di safe-area zone (home indicator iPhone) tidak terlihat
          bocor. Posisi absolute supaya tidak mengganggu pointer event pill.
          Top-edge gradient ke transparent supaya floating look tetap natural. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 bottom-0 h-[calc(env(safe-area-inset-bottom)+12px)] bg-gradient-to-t from-white via-white/95 to-white/0"
      />
      <div className="pointer-events-auto relative mx-3 mb-2">
        <div className="relative grid h-[60px] grid-cols-4 overflow-hidden rounded-full border border-black/[0.06] bg-white/95 shadow-[0_10px_32px_rgba(15,40,80,0.16)] backdrop-blur-xl backdrop-saturate-150">
          <span
            aria-hidden
            className="pointer-events-none absolute left-0 top-1.5 bottom-1.5 w-1/4 rounded-full bg-natalo-50 transition-transform duration-[450ms] ease-[cubic-bezier(0.34,1.56,0.64,1)]"
            style={{ transform: `translateX(${activeIndex * 100}%)` }}
          />
          {ITEMS.map((item, i) => {
            const active = i === activeIndex;
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
                  <NavIcon name={item.icon} active={active} />
                  {item.href === "/cart" && cartCount > 0 && (
                    <span className="absolute -right-2.5 -top-1.5 flex h-[18px] min-w-[18px] items-center justify-center rounded-full border-2 border-white bg-[#1E5FBF] px-1 text-[9px] font-black leading-none text-white">
                      {cartCount > 99 ? "99+" : cartCount}
                    </span>
                  )}
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
