"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { loadCart } from "@/lib/cart";

export function CartCount() {
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
    <Link href="/cart" className="relative inline-flex items-center gap-1 text-xs font-bold text-gray-700 sm:text-sm">
      <svg className="h-5 w-5 text-gray-700 sm:h-6 sm:w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.8}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 3h1.386c.51 0 .955.343 1.087.835l.383 1.437M7.5 14.25a3 3 0 0 0-3 3h15.75m-12.75-3h11.218c1.121-2.3 2.1-4.684 2.924-7.138a60.114 60.114 0 0 0-16.536-1.84M7.5 14.25 5.106 5.272M6 20.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0Zm12.75 0a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0Z" />
      </svg>
      <span className="hidden xs:inline">Keranjang</span>
      {count > 0 && (
        <span className="absolute -right-2 -top-2 flex h-4 w-4 items-center justify-center rounded-full bg-natalo-600 text-[10px] font-bold text-white">
          {count > 9 ? "9+" : count}
        </span>
      )}
    </Link>
  );
}
