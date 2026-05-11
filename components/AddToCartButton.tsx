"use client";

import { useState } from "react";
import { StoreProduct } from "@/lib/products";
import { AddToCartBottomSheet } from "@/components/AddToCartBottomSheet";

export function AddToCartButton({ product }: { product: StoreProduct }) {
  const [added, setAdded] = useState(false);
  const [sheetOpen, setSheetOpen] = useState(false);

  const price =
    product.discountPrice !== null && product.discountPrice < product.price
      ? product.discountPrice
      : product.price;

  const item = {
    productId: product.id,
    slug: product.slug,
    variantId: null,
    variantLabel: null,
    name: product.name,
    price,
    weightGram: product.weightGram,
    stock: product.stock,
    imageUrl: product.imageUrl,
    minimumQuantity: (product as StoreProduct & { minimumQuantity?: number | null })
      .minimumQuantity,
  };

  const onAdded = () => {
    setAdded(true);
    setTimeout(() => setAdded(false), 1800);
  };

  return (
    <>
      <button
        type="button"
        onClick={() => setSheetOpen(true)}
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
      <AddToCartBottomSheet
        open={sheetOpen}
        item={item}
        onClose={() => setSheetOpen(false)}
        onAdded={onAdded}
      />
    </>
  );
}
