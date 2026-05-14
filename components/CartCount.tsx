"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { PetCartIcon } from "@/components/PetCartIcon";
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
          ? "nat-header-action-glass relative inline-flex h-11 w-11 items-center justify-center rounded-full text-slate-700 transition active:scale-95"
          : "relative inline-flex items-center gap-1 text-xs font-bold text-gray-700 sm:text-sm"
      }
      aria-label="Keranjang"
    >
      <PetCartIcon
        className={compact ? "h-[22px] w-[22px]" : "h-5 w-5 text-gray-700 sm:h-6 sm:w-6"}
        pawClassName={
          compact
            ? "absolute -bottom-0.5 -right-1 h-3.5 w-3.5 rounded-full bg-white p-0.5 text-[#1E5FBF] shadow-sm"
            : "absolute -bottom-0.5 -right-1 h-3 w-3 rounded-full bg-white p-0.5 text-[#1E5FBF] shadow-sm"
        }
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
