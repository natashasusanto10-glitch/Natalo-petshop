"use client";

import { useState } from "react";
import Link from "next/link";
import { StoreProduct } from "@/lib/products";

type CartItem = {
  productId: string;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
  imageUrl?: string | null;
};

function getCart(): CartItem[] {
  if (typeof window === "undefined") return [];
  const raw = localStorage.getItem("cart");
  return raw ? JSON.parse(raw) : [];
}

function saveCart(items: CartItem[]) {
  localStorage.setItem("cart", JSON.stringify(items));
  window.dispatchEvent(new Event("cart-updated"));
}

export function ProductActions({ product }: { product: StoreProduct }) {
  const [qty, setQty] = useState(1);
  const [added, setAdded] = useState(false);

  const price = product.memberPrice ?? product.price;
  const outOfStock = product.stock === 0;

  function addToCart() {
    if (outOfStock) return;
    const cart = getCart();
    const existing = cart.find((i) => i.productId === product.id);
    if (existing) {
      existing.quantity += qty;
    } else {
      cart.push({
        productId: product.id,
        name: product.name,
        price,
        quantity: qty,
        weightGram: product.weightGram,
        imageUrl: product.imageUrl,
      });
    }
    saveCart(cart);
    setAdded(true);
    setTimeout(() => setAdded(false), 3000);
  }

  return (
    <div className="space-y-4">
      {/* Quantity selector */}
      <div>
        <p className="mb-2 text-sm font-medium text-gray-700">Jumlah</p>
        <div className="flex items-center gap-3">
          <button
            onClick={() => setQty((q) => Math.max(1, q - 1))}
            className="flex h-10 w-10 items-center justify-center rounded-full border border-gray-200 text-lg font-bold text-gray-700 transition hover:border-orange-400 hover:text-orange-500 disabled:opacity-40"
            disabled={qty <= 1}
          >
            −
          </button>
          <span className="w-8 text-center text-lg font-bold text-gray-900">{qty}</span>
          <button
            onClick={() => setQty((q) => Math.min(product.stock || 99, q + 1))}
            className="flex h-10 w-10 items-center justify-center rounded-full border border-gray-200 text-lg font-bold text-gray-700 transition hover:border-orange-400 hover:text-orange-500 disabled:opacity-40"
            disabled={outOfStock || qty >= product.stock}
          >
            +
          </button>
          {product.stock > 0 && (
            <span className="text-sm text-gray-400">Stok: {product.stock}</span>
          )}
        </div>
      </div>

      {/* Add to cart */}
      <button
        onClick={addToCart}
        disabled={outOfStock}
        className={`w-full rounded-full py-4 text-sm font-bold text-white transition ${
          added
            ? "bg-green-500"
            : outOfStock
            ? "cursor-not-allowed bg-gray-300"
            : "bg-orange-500 hover:bg-orange-600"
        }`}
      >
        {outOfStock ? "Stok Habis" : added ? "✓ Ditambahkan!" : "Tambah ke Keranjang"}
      </button>

      {/* Toast setelah tambah */}
      {added && (
        <div className="flex items-center justify-between rounded-2xl bg-green-50 px-4 py-3 text-sm">
          <span className="font-semibold text-green-700">Produk masuk keranjang 🎉</span>
          <Link
            href="/cart"
            className="ml-4 shrink-0 rounded-full bg-green-600 px-4 py-1.5 text-xs font-bold text-white transition hover:bg-green-700"
          >
            Lihat Keranjang →
          </Link>
        </div>
      )}
    </div>
  );
}
