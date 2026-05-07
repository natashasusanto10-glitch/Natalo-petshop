"use client";

import { useState } from "react";
import { StoreProduct } from "@/lib/products";
import { loadCart, saveCart } from "@/lib/cart";

export function AddToCartButton({ product }: { product: StoreProduct }) {
  const [added, setAdded] = useState(false);

  const add = () => {
    const cart = loadCart();
    const price =
      product.discountPrice !== null && product.discountPrice < product.price
        ? product.discountPrice
        : product.price;
    const existing = cart.find((item) => item.productId === product.id);

    if (existing) {
      existing.quantity = Math.min(product.stock, existing.quantity + 1);
      existing.stock = product.stock;
      existing.imageUrl = product.imageUrl;
    } else {
      cart.push({
        productId: product.id,
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
    setTimeout(() => setAdded(false), 2000);
  };

  return (
    <button
      onClick={add}
      disabled={product.stock <= 0}
      className={`w-full rounded-full px-6 py-4 text-sm font-bold text-white transition ${
        product.stock <= 0
          ? "cursor-not-allowed bg-zinc-300"
          : added
          ? "bg-green-600"
          : "bg-zinc-950 hover:bg-zinc-800"
      }`}
    >
      {added ? "Ditambahkan ke keranjang ✓" : "+ Keranjang"}
    </button>
  );
}
