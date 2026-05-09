"use client";

import { useState } from "react";
import { StoreProduct } from "@/lib/products";
import { addItemToCart } from "@/lib/cart-actions";

export function AddToCartButton({ product }: { product: StoreProduct }) {
  const [added, setAdded] = useState(false);

  const add = () => {
    const price =
      product.discountPrice !== null && product.discountPrice < product.price
        ? product.discountPrice
        : product.price;

    const result = addItemToCart({
      productId: product.id,
      variantId: null,
      variantLabel: null,
      name: product.name,
      price,
      quantity: 1,
      subtotal: price,
      weightGram: product.weightGram,
      stock: product.stock,
      imageUrl: product.imageUrl,
    });

    if (result.ok) {
      setAdded(true);
      setTimeout(() => setAdded(false), 1800);
    }
  };

  return (
    <button
      type="button"
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
      {added ? "Ditambahkan" : "Masukkan Keranjang"}
    </button>
  );
}
