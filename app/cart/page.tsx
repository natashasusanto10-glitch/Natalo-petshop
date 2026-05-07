"use client";

import Image from "next/image";
import Link from "next/link";
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
  stock?: number;
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
          {items.map((item) => {
            const itemKey = `${item.productId}:${item.variantId ?? ""}`;
            return (
              <div
                key={itemKey}
                className="flex items-center justify-between gap-4 rounded-2xl border border-gray-100 bg-white p-4 shadow-sm"
              >
                <div className="flex items-center gap-4">
                  <div className="relative flex h-14 w-14 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-gray-100 text-2xl">
                    {item.imageUrl ? (
                      <Image
                        src={item.imageUrl}
                        alt={item.name}
                        fill
                        sizes="56px"
                        className="object-cover"
                      />
                    ) : (
                      <span>🐾</span>
                    )}
                  </div>
                  <div>
                    <p className="font-semibold text-gray-900">{item.name}</p>
                    {item.variantLabel && (
                      <p className="mt-0.5 text-xs font-medium text-natalo-600">{item.variantLabel}</p>
                    )}
                    <p className="mt-0.5 text-sm text-gray-400">{formatRupiah(item.price)} / item</p>
                    {item.stock !== undefined && (
                      <p className="mt-0.5 text-xs text-gray-400">Stok: {item.stock}</p>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-3">
                  <button
                    onClick={() => updateQty(itemKey, item.quantity - 1)}
                    disabled={item.quantity <= 1}
                    className="flex h-8 w-8 items-center justify-center rounded-full border border-gray-200 text-gray-600 transition hover:border-natalo-400 hover:text-natalo-600 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    −
                  </button>
                  <span className="w-6 text-center font-bold text-gray-900">{item.quantity}</span>
                  <button
                    onClick={() => updateQty(itemKey, item.quantity + 1)}
                    disabled={item.stock !== undefined && item.quantity >= item.stock}
                    className="flex h-8 w-8 items-center justify-center rounded-full border border-gray-200 text-gray-600 transition hover:border-natalo-400 hover:text-natalo-600 disabled:opacity-40"
                  >
                    +
                  </button>
                  <button
                    onClick={() => updateQty(itemKey, 0)}
                    className="ml-1 text-xs text-gray-300 transition hover:text-red-400"
                  >
                    Hapus
                  </button>
                </div>

                <p className="min-w-[80px] text-right font-bold text-gray-900">
                  {formatRupiah(item.price * item.quantity)}
                </p>
              </div>
            );
          })}

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
