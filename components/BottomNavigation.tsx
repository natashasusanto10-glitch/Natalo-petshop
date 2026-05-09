"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import type { ReactNode } from "react";
import { loadCart } from "@/lib/cart";

type NavIconName = "home" | "bone" | "bag" | "person";

const ITEMS: { href: string; label: string; icon: NavIconName }[] = [
  { href: "/", label: "Beranda", icon: "home" },
  { href: "/kategori", label: "Kategori", icon: "bone" },
  { href: "/cart", label: "Keranjang", icon: "bag" },
  { href: "/member", label: "Akun", icon: "person" },
];

function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  if (href === "/kategori") return pathname === "/kategori" || pathname.startsWith("/products");
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
    bone: (
      <path d="M9 8 a3.5 3 0 0 0 -3 4.7 a3 3 0 0 0 0 5.6 A3.5 3 0 0 0 9 23 a3 3 0 0 0 4-1.5 L18 21 a3 3 0 0 0 4 1.5 a3.5 3 0 0 0 3-4.7 a3 3 0 0 0 0-5.6 A3.5 3 0 0 0 22 7.5 a3 3 0 0 0-4 1.5 L13 9 a3 3 0 0 0-4-1.5 Z" />
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
      className={`relative flex h-7 w-10 items-center justify-center transition-transform duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${
        active ? "-translate-y-0.5 scale-105" : ""
      }`}
    >
      <span
        aria-hidden
        className={`absolute inset-0 rounded-xl transition-colors ${
          active ? "bg-[#EFF6FF]" : "bg-transparent"
        }`}
      />
      <svg
        aria-hidden="true"
        viewBox="0 0 32 32"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
        className="relative h-6 w-6"
      >
        {paths[name]}
      </svg>
    </span>
  );
}

export function BottomNavigation() {
  const pathname = usePathname();
  const [cartCount, setCartCount] = useState(0);

  useEffect(() => {
    function syncCart() {
      const items = loadCart();
      setCartCount(items.reduce((sum, item) => sum + Number(item.quantity || 0), 0));
    }

    function onStorage(e: StorageEvent) {
      if (e.key === "cart") syncCart();
    }
    syncCart();
    window.addEventListener("cart-updated", syncCart);
    window.addEventListener("storage", onStorage);
    return () => {
      window.removeEventListener("cart-updated", syncCart);
      window.removeEventListener("storage", onStorage);
    };
  }, []);

  if (pathname === "/checkout" || pathname?.startsWith("/checkout/")) return null;

  return (
    <nav className="fixed inset-x-0 bottom-0 z-50 border-t border-[#f0f0f0] bg-white py-2 shadow-[0_-2px_12px_rgba(0,0,0,0.05)] md:hidden [padding-bottom:calc(4px+env(safe-area-inset-bottom))]">
      <div className="grid grid-cols-4">
        {ITEMS.map((item) => {
          const active = isActive(pathname, item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`relative flex min-h-12 flex-col items-center justify-center gap-0.5 px-1 py-1 text-[10px] font-bold transition active:opacity-90 ${
                active ? "text-[#1E5FBF]" : "text-[#9ca3af]"
              }`}
            >
              <NavIcon name={item.icon} active={active} />
              <span>{item.label}</span>
              <span
                className={`mt-0.5 h-[3px] w-4 rounded-full transition-colors ${
                  active ? "bg-[#1E5FBF]" : "bg-transparent"
                }`}
              />
              {item.href === "/cart" && cartCount > 0 && (
                <span className="absolute right-[23%] top-0.5 flex h-[18px] min-w-[18px] items-center justify-center rounded-full border-2 border-white bg-[#1E5FBF] px-1 text-[9px] font-black leading-none text-white">
                  {cartCount > 99 ? "99+" : cartCount}
                </span>
              )}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
