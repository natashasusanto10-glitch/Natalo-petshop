"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

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
  try { return JSON.parse(localStorage.getItem("cart") ?? "[]"); } catch { return []; }
}

function saveCart(items: CartItem[]) {
  localStorage.setItem("cart", JSON.stringify(items));
  window.dispatchEvent(new Event("cart-updated"));
}

interface Props {
  product: {
    id: string;
    slug: string;
    name: string;
    price: number;
    discountPrice: number | null;
    stock: number;
    weightGram: number;
    imageUrl: string | null;
    isActive: boolean;
    hasVariants: boolean;
  };
  className?: string;
}

/**
 * Tombol "+ Keranjang" cepat untuk halaman wishlist/favorit.
 * - Produk varian → redirect ke detail (pilih varian)
 * - Produk non-varian → langsung add ke cart
 * - Produk inactive / stok 0 → disabled
 */
export function QuickAddToCart({ product, className }: Props) {
  const router = useRouter();
  const [added, setAdded] = useState(false);

  const isOut = product.stock === 0;
  const isUnavailable = !product.isActive;

  if (isUnavailable) {
    return (
      <button
        type="button"
        disabled
        className={`w-full rounded-full bg-gray-200 py-2 text-xs font-bold text-gray-400 ${className ?? ""}`}
      >
        Tidak tersedia
      </button>
    );
  }

  if (product.hasVariants) {
    return (
      <button
        type="button"
        onClick={() => router.push(`/products/${product.slug}`)}
        className={`w-full rounded-full bg-natalo-600 py-2 text-xs font-bold text-white hover:bg-natalo-700 ${className ?? ""}`}
      >
        Pilih Varian →
      </button>
    );
  }

  if (isOut) {
    return (
      <button
        type="button"
        disabled
        className={`w-full rounded-full bg-gray-200 py-2 text-xs font-bold text-gray-400 ${className ?? ""}`}
      >
        Stok Habis
      </button>
    );
  }

  function addToCart() {
    const price =
      product.discountPrice !== null && product.discountPrice < product.price
        ? product.discountPrice
        : product.price;

    const cart = loadCart();
    const existing = cart.find(
      (i) => i.productId === product.id && !i.variantId
    );
    if (existing) {
      existing.quantity = Math.min(product.stock, existing.quantity + 1);
      existing.stock = product.stock;
      existing.imageUrl = product.imageUrl;
    } else {
      cart.push({
        productId: product.id,
        variantId: null,
        variantLabel: null,
        name: product.name,
        price,
        quantity: 1,
        weightGram: product.weightGram,
        stock: product.stock,
        imageUrl: product.imageUrl,
      });
    }
    saveCart(cart);
    setAdded(true);
    setTimeout(() => setAdded(false), 1800);
  }

  return (
    <button
      type="button"
      onClick={addToCart}
      className={`w-full rounded-full py-2 text-xs font-bold text-white transition ${
        added ? "bg-green-500" : "bg-natalo-600 hover:bg-natalo-700"
      } ${className ?? ""}`}
    >
      {added ? "✓ Ditambahkan" : "+ Keranjang"}
    </button>
  );
}
