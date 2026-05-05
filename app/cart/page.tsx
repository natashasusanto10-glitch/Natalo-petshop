"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { formatRupiah } from "@/lib/format";

type CartItem = {
  productId: string;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
};

function loadCart(): CartItem[] {
  if (typeof window === "undefined") return [];
  const raw = localStorage.getItem("cart");
  return raw ? JSON.parse(raw) : [];
}

function saveCart(items: CartItem[]) {
  localStorage.setItem("cart", JSON.stringify(items));
  window.dispatchEvent(new Event("cart-updated"));
}

export default function CartPage() {
  const [items, setItems] = useState<CartItem[]>([]);

  useEffect(() => setItems(loadCart()), []);

  const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);

  function updateQty(productId: string, quantity: number) {
    const next = items
      .map((item) => (item.productId === productId ? { ...item, quantity } : item))
      .filter((item) => item.quantity > 0);
    setItems(next);
    saveCart(next);
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-10">
      <h1 className="text-3xl font-black tracking-tight text-gray-900">Keranjang</h1>

      {items.length === 0 ? (
        <div className="mt-10 rounded-3xl border border-gray-100 bg-gray-50 p-12 text-center">
          <span className="text-6xl">🛒</span>
          <p className="mt-4 font-semibold text-gray-500">Keranjang masih kosong.</p>
          <Link
            href="/products"
            className="mt-5 inline-flex rounded-full bg-orange-500 px-7 py-3 text-sm font-bold text-white transition hover:bg-orange-600"
          >
            Lihat produk
          </Link>
        </div>
      ) : (
        <div className="mt-8 space-y-4">
          {items.map((item) => (
            <div
              key={item.productId}
              className="flex items-center justify-between gap-4 rounded-2xl border border-gray-100 bg-white p-4 shadow-sm"
            >
              <div className="flex items-center gap-4">
                <div className="flex h-14 w-14 items-center justify-center rounded-xl bg-gray-100 text-2xl">
                  🐾
                </div>
                <div>
                  <p className="font-semibold text-gray-900">{item.name}</p>
                  <p className="mt-0.5 text-sm text-gray-400">{formatRupiah(item.price)} / item</p>
                </div>
              </div>

              <div className="flex items-center gap-3">
                <button
                  onClick={() => updateQty(item.productId, item.quantity - 1)}
                  className="flex h-8 w-8 items-center justify-center rounded-full border border-gray-200 text-gray-600 transition hover:border-orange-400 hover:text-orange-500"
                >
                  −
                </button>
                <span className="w-6 text-center font-bold text-gray-900">{item.quantity}</span>
                <button
                  onClick={() => updateQty(item.productId, item.quantity + 1)}
                  className="flex h-8 w-8 items-center justify-center rounded-full border border-gray-200 text-gray-600 transition hover:border-orange-400 hover:text-orange-500"
                >
                  +
                </button>
                <button
                  onClick={() => updateQty(item.productId, 0)}
                  className="ml-1 text-xs text-gray-300 transition hover:text-red-400"
                >
                  Hapus
                </button>
              </div>

              <p className="min-w-[80px] text-right font-bold text-gray-900">
                {formatRupiah(item.price * item.quantity)}
              </p>
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
              className="mt-5 flex w-full items-center justify-center rounded-full bg-orange-500 py-4 text-sm font-bold text-white transition hover:bg-orange-600"
            >
              Lanjut Checkout →
            </Link>
            <Link
              href="/products"
              className="mt-3 flex w-full items-center justify-center rounded-full border border-gray-200 py-3 text-sm font-semibold text-gray-600 transition hover:border-orange-300 hover:text-orange-500"
            >
              Tambah produk lagi
            </Link>
          </div>
        </div>
      )}
    </div>
  );
}
