"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

const ITEMS = [
  { href: "/", label: "Beranda", icon: "🏠" },
  { href: "/kategori", label: "Kategori", icon: "🗂️" },
  { href: "/cart", label: "Keranjang", icon: "🛒" },
  { href: "/member", label: "Akun", icon: "👤" },
];

function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  if (href === "/kategori") return pathname === "/kategori" || pathname.startsWith("/products");
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function BottomNavigation() {
  const pathname = usePathname();
  const [cartCount, setCartCount] = useState(0);

  useEffect(() => {
    function syncCart() {
      try {
        const raw = localStorage.getItem("cart");
        const items = raw ? JSON.parse(raw) : [];
        const total = Array.isArray(items)
          ? items.reduce((sum, item) => sum + Number(item.quantity || 0), 0)
          : 0;
        setCartCount(total);
      } catch {
        setCartCount(0);
      }
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

  return (
    <nav className="fixed inset-x-0 bottom-0 z-50 border-t border-[#f0f0f0] bg-white py-2 shadow-[0_-2px_12px_rgba(0,0,0,0.05)] md:hidden [padding-bottom:calc(8px+env(safe-area-inset-bottom))]">
      <div className="grid grid-cols-4">
        {ITEMS.map((item) => {
          const active = isActive(pathname, item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`relative flex min-h-12 flex-col items-center justify-center gap-1 text-[10px] font-bold transition active:opacity-90 ${
                active ? "text-[#E8711F]" : "text-[#999]"
              }`}
            >
              <span className="text-[22px] leading-none">{item.icon}</span>
              <span>{item.label}</span>
              <span
                className={`h-1 w-4 rounded-full transition ${
                  active ? "bg-[#E8711F]" : "bg-transparent"
                }`}
              />
              {item.href === "/cart" && cartCount > 0 && (
                <span className="absolute right-[23%] top-0 flex h-[18px] min-w-[18px] items-center justify-center rounded-full bg-[#E8711F] px-1 text-[10px] font-black leading-none text-white">
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
