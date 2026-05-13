"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { IoBagOutline } from "react-icons/io5";
import { loadCart } from "@/lib/cart";

type CartCountProps = {
  compact?: boolean;
};

export function CartCount({ compact = false }: CartCountProps) {
  const [count, setCount] = useState(0);

  function sync() {
    const items = loadCart();
    setCount(items.reduce((s, i) => s + i.quantity, 0));
  }

  useEffect(() => {
    sync();
    window.addEventListener("cart-updated", sync);
    function onStorage(e: StorageEvent) {
      if (e.key?.startsWith("cart")) sync();
    }
    window.addEventListener("storage", onStorage);
    return () => {
      window.removeEventListener("cart-updated", sync);
      window.removeEventListener("storage", onStorage);
    };
  }, []);

  return (
    <Link
      href="/cart"
      className={
        compact
          ? "relative inline-flex h-11 w-11 items-center justify-center rounded-full bg-white text-slate-700 shadow-sm ring-1 ring-slate-100 transition active:scale-95"
          : "relative inline-flex items-center gap-1 text-xs font-bold text-gray-700 sm:text-sm"
      }
      aria-label="Keranjang"
    >
      <IoBagOutline
        className={compact ? "h-6 w-6" : "h-5 w-5 text-gray-700 sm:h-6 sm:w-6"}
        aria-hidden="true"
      />
      {!compact && <span className="hidden xs:inline">Keranjang</span>}
      {count > 0 && (
        <span
          className={
            compact
              ? "absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-black leading-none text-white ring-2 ring-white"
              : "absolute -right-2 -top-2 flex h-4 w-4 items-center justify-center rounded-full bg-natalo-600 text-[10px] font-bold text-white"
          }
        >
          {count > 99 ? "99+" : count}
        </span>
      )}
    </Link>
  );
}
