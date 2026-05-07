"use client";

import Image from "next/image";
import Link from "next/link";
import Image from "next/image";
import { useEffect, useState } from "react";
import { formatRupiah } from "@/lib/format";
import { EmptyCart } from "@/components/LoadingEmptyStates";

type CartItem = {
  productId: string;
  variantId?: string | null;
  variantLabel?: string | null;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
  imageUrl?: string | null;
};

function loadCart(): CartItem[] {
  if (typeof window === "undefined") return [];
  const raw = localStorage.getItem("cart");
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    // localStorage corrupted — reset cart agar halaman tidak crash
    localStorage.removeItem("cart");
    return [];
  }
}

function saveCart(items: CartItem[]) {
  localStorage.setItem("cart", JSON.stringify(items));
  window.dispatchEvent(new Event("cart-updated"));
}

export default function CartPage() {
  const [items, setItems] = useState<CartItem[]>([]);

  useEffect(() => {
    function syncCart() {
      setItems(loadCart());
    }

    syncCart();
    window.addEventListener("cart-updated", syncCart);
    return () => window.removeEventListener("cart-updated", syncCart);
  }, []);

  const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);

  function updateQty(key: string, quantity: number) {
    const next = items
      .map((item) =>
        `${item.productId}:${item.variantId ?? ""}` === key
          ? { ...item, quantity: Math.min(quantity, item.stock ?? quantity) }
          : item
      )
      .filter((item) => item.quantity > 0);
    setItems(next);
    saveCart(next);
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-10">
      <h1 className="text-3xl font-black tracking-tight text-gray-900">Keranjang</h1>

      {items.length === 0 ? (
        <div className="mt-10 rounded-2xl border border-gray-100 bg-white">
          <EmptyCart />
        </div>
      ) : (
        <div className="mt-8 space-y-4">
          {items.map((item) => (
            <div
              key={item.productId}
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
                  <p className="mt-0.5 text-sm text-gray-400">{formatRupiah(item.price)} / item</p>
                </div>
                <p className="shrink-0 font-bold text-gray-900">{formatRupiah(item.price * item.quantity)}</p>
              </div>
              <div className="mt-3 flex items-center justify-between">
                <div className="flex items-center gap-1">
                  <button
                    onClick={() => updateQty(item.productId, item.quantity - 1)}
                    className="flex h-11 w-11 items-center justify-center rounded-full border border-gray-200 text-lg text-gray-600 transition hover:border-orange-400 hover:text-orange-500"
                    aria-label="Kurangi"
                  >
                    −
                  </button>
                  <span className="w-9 text-center font-bold text-gray-900">{item.quantity}</span>
                  <button
                    onClick={() => updateQty(item.productId, item.quantity + 1)}
                    className="flex h-11 w-11 items-center justify-center rounded-full border border-gray-200 text-lg text-gray-600 transition hover:border-orange-400 hover:text-orange-500"
                    aria-label="Tambah"
                  >
                    +
                  </button>
                </div>
                <button
                  onClick={() => updateQty(item.productId, 0)}
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
          ))}

          <div className="rounded-2xl bg-gray-50 p-5">
            <div className="flex items-center justify-between">
              <span className="font-semibold text-gray-700">Subtotal</span>
              <span className="text-xl font-black text-gray-900">{formatRupiah(subtotal)}</span>
            </div>
            <p className="mt-2 text-xs text-gray-400">Ongkir dihitung saat checkout.</p>
            <Link
              href="/checkout"
              className="mt-5 flex w-full items-center justify-center rounded-full bg-natalo-600 py-4 text-sm font-bold text-white transition hover:bg-natalo-700"
            >
              Lanjut Checkout →
            </Link>
            <Link
              href="/products"
              className="mt-3 flex w-full items-center justify-center rounded-full border border-gray-200 py-3 text-sm font-semibold text-gray-600 transition hover:border-natalo-300 hover:text-natalo-600"
            >
              Tambah produk lagi
            </Link>
          </div>
        </div>
      )}
    </div>
  );
}
