"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { StoreProduct } from "@/lib/products";
import { loadCart, saveCart } from "@/lib/cart";

export function ProductActions({ product }: { product: StoreProduct }) {
  const [qty, setQty] = useState(1);
  const [added, setAdded] = useState(false);

  const price =
    product.discountPrice !== null && product.discountPrice < product.price
      ? product.discountPrice
      : product.price;
  const outOfStock = product.stock === 0;

  // Listen trigger dari StickyAddToCartBar
  useEffect(() => {
    function onTrigger() {
      addToCart();
    }
    window.addEventListener("pdp-add-to-cart", onTrigger);
    return () => window.removeEventListener("pdp-add-to-cart", onTrigger);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [qty, outOfStock]);

  function addToCart() {
    if (outOfStock) return;
    const cart = loadCart();
    const existing = cart.find((i) => i.productId === product.id);
    if (existing) {
      existing.quantity = Math.min(product.stock, existing.quantity + qty);
      existing.stock = product.stock;
      existing.imageUrl = product.imageUrl;
    } else {
      cart.push({
        productId: product.id,
        name: product.name,
        price,
        quantity: qty,
        weightGram: product.weightGram,
        imageUrl: product.imageUrl,
        stock: product.stock,
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
            className="flex h-10 w-10 items-center justify-center rounded-full border border-gray-200 text-lg font-bold text-gray-700 transition hover:border-natalo-400 hover:text-natalo-600 disabled:opacity-40"
            disabled={qty <= 1}
          >
            −
          </button>
          <span className="w-8 text-center text-lg font-bold text-gray-900">{qty}</span>
          <button
            onClick={() => setQty((q) => Math.min(product.stock || 99, q + 1))}
            className="flex h-10 w-10 items-center justify-center rounded-full border border-gray-200 text-lg font-bold text-gray-700 transition hover:border-natalo-400 hover:text-natalo-600 disabled:opacity-40"
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
            : "bg-natalo-600 hover:bg-natalo-700"
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
