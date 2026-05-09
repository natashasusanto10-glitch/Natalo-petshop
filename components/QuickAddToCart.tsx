"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { AddToCartBottomSheet } from "@/components/AddToCartBottomSheet";

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

export function QuickAddToCart({ product, className }: Props) {
  const router = useRouter();
  const [added, setAdded] = useState(false);
  const [sheetOpen, setSheetOpen] = useState(false);

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
        Pilih Varian
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

  function cartItem() {
    const price =
      product.discountPrice !== null && product.discountPrice < product.price
        ? product.discountPrice
        : product.price;

    return {
      productId: product.id,
      variantId: null,
      variantLabel: null,
      name: product.name,
      price,
      weightGram: product.weightGram,
      stock: product.stock,
      imageUrl: product.imageUrl,
    };
  }

  function onAdded() {
    setAdded(true);
    setTimeout(() => setAdded(false), 1800);
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setSheetOpen(true)}
        className={`w-full rounded-full py-2 text-xs font-bold text-white transition ${
          added ? "bg-green-500" : "bg-natalo-600 hover:bg-natalo-700"
        } ${className ?? ""}`}
      >
        {added ? "Ditambahkan" : "+ Keranjang"}
      </button>
      <AddToCartBottomSheet
        open={sheetOpen}
        item={cartItem()}
        onClose={() => setSheetOpen(false)}
        onAdded={onAdded}
      />
    </>
  );
}
