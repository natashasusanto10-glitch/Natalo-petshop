"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { formatRupiah } from "@/lib/format";
import { EmptyCart } from "@/components/LoadingEmptyStates";
import { loadCart, saveCart, type CartItem } from "@/lib/cart";

export default function CartPage() {
  const [items, setItems] = useState<CartItem[]>([]);

  useEffect(() => {
    function syncCart() {
      setItems(loadCart());
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

  const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);

  function updateQty(key: string, quantity: number) {
    const next = items
      .map((item) => {
        if (`${item.productId}:${item.variantId ?? ""}` !== key) return item;
        const max = item.stock ?? Infinity;
        return { ...item, quantity: Math.min(quantity, max) };
      })
      .filter((item) => item.quantity > 0);
    setItems(next);
    saveCart(next);
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-4 pb-32 md:py-10 md:pb-10">
      <h1 className="text-2xl font-black tracking-tight text-gray-900 md:text-3xl">Keranjang</h1>

      {items.length === 0 ? (
        <div className="mt-6 rounded-2xl border border-gray-100 bg-white md:mt-10">
          <EmptyCart />
        </div>
      ) : (
        <div className="mt-4 space-y-4 md:mt-8">
          {items.map((item) => {
            const key = `${item.productId}:${item.variantId ?? ""}`;
            return (
              <div
                key={key}
                className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm"
              >
                <div className="flex gap-3">
                  <div className="relative h-16 w-16 shrink-0 overflow-hidden rounded-xl bg-gray-100">
                    {item.imageUrl ? (
                      <Image src={item.imageUrl} alt={item.name} fill className="object-cover" />
                    ) : (
                      <div className="flex h-full w-full items-center justify-center text-2xl">🐾</div>
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-gray-900 leading-snug">{item.name}</p>
                    {item.variantLabel && (
                      <p className="mt-0.5 text-xs text-blue-600">{item.variantLabel}</p>
                    )}
                    <p className="mt-0.5 text-sm text-gray-400">{formatRupiah(item.price)} / item</p>
                  </div>
                  <p className="shrink-0 font-bold text-gray-900">{formatRupiah(item.price * item.quantity)}</p>
                </div>
                <div className="mt-3 flex items-center justify-between">
                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => updateQty(key, item.quantity - 1)}
                      className="flex h-11 w-11 items-center justify-center rounded-full border border-gray-200 text-lg text-gray-600 transition hover:border-blue-400 hover:text-blue-500"
                      aria-label="Kurangi"
                    >
                      −
                    </button>
                    <span className="w-9 text-center font-bold text-gray-900">{item.quantity}</span>
                    <button
                      onClick={() => updateQty(key, item.quantity + 1)}
                      disabled={item.stock != null && item.quantity >= item.stock}
                      className="flex h-11 w-11 items-center justify-center rounded-full border border-gray-200 text-lg text-gray-600 transition hover:border-blue-400 hover:text-blue-500 disabled:cursor-not-allowed disabled:opacity-40"
                      aria-label="Tambah"
                    >
                      +
                    </button>
                    {item.stock != null && item.quantity >= item.stock && (
                      <span className="ml-2 text-xs text-amber-600">Maks. {item.stock}</span>
                    )}
                  </div>
                  <button
                    onClick={() => updateQty(key, 0)}
                    className="flex h-11 items-center gap-1.5 rounded-full px-3 text-sm text-gray-400 transition hover:text-red-500"
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-4 w-4">
                      <polyline points="3 6 5 6 21 6" />
                      <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
                      <path d="M10 11v6M14 11v6" />
                    </svg>
                    Hapus
                  </button>
                </div>
              </div>
            );
          })}

          {/* Desktop summary panel */}
          <div className="hidden rounded-2xl bg-gray-50 p-5 md:block">
            <div className="flex items-center justify-between">
              <span className="font-semibold text-gray-700">Subtotal</span>
              <span className="text-xl font-black text-gray-900">{formatRupiah(subtotal)}</span>
            </div>
            <p className="mt-2 text-xs text-gray-400">Ongkir dihitung saat checkout.</p>
            <Link
              href="/checkout"
              className="mt-5 flex w-full items-center justify-center rounded-full bg-blue-500 py-4 text-sm font-bold text-white transition hover:bg-blue-600"
            >
              Lanjut Checkout →
            </Link>
            <Link
              href="/products"
              className="mt-3 flex w-full items-center justify-center rounded-full border border-gray-200 py-3 text-sm font-semibold text-gray-600 transition hover:border-blue-300 hover:text-blue-600"
            >
              Tambah produk lagi
            </Link>
          </div>
        </div>
      )}

      {/* Mobile sticky bottom checkout bar */}
      {items.length > 0 && (
        <div className="fixed inset-x-0 bottom-[70px] z-40 border-t border-gray-100 bg-white px-4 py-3 shadow-[0_-4px_12px_rgba(0,0,0,0.06)] md:hidden [padding-bottom:calc(12px+env(safe-area-inset-bottom))]">
          <div className="flex items-center gap-3">
            <div className="min-w-0 flex-1">
              <p className="text-xs text-gray-500">Subtotal</p>
              <p className="truncate text-base font-black text-gray-900">{formatRupiah(subtotal)}</p>
            </div>
            <Link
              href="/checkout"
              className="flex h-12 shrink-0 items-center justify-center rounded-full bg-blue-500 px-6 text-sm font-bold text-white active:opacity-90"
            >
              Checkout →
            </Link>
          </div>
        </div>
      )}
    </div>
  );
}
