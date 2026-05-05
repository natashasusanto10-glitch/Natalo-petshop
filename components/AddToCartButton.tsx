"use client";

import { useState } from "react";
import { StoreProduct } from "@/lib/products";

type CartItem = {
  productId: string;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
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

export function AddToCartButton({ product }: { product: StoreProduct }) {
  const [added, setAdded] = useState(false);

  const add = () => {
    const cart = getCart();
    const price = product.memberPrice ?? product.price;
    const existing = cart.find((item) => item.productId === product.id);

    if (existing) {
      existing.quantity += 1;
    } else {
      cart.push({
        productId: product.id,
        name: product.name,
        price,
        quantity: 1,
        weightGram: product.weightGram,
      });
    }

    saveCart(cart);
    setAdded(true);
    setTimeout(() => setAdded(false), 2000);
  };

  return (
    <button
      onClick={add}
      className={`w-full rounded-full px-6 py-4 text-sm font-bold text-white transition ${
        added ? "bg-green-600" : "bg-zinc-950 hover:bg-zinc-800"
      }`}
    >
      {added ? "Ditambahkan ke keranjang ✓" : "Tambah ke Keranjang"}
    </button>
  );
}
