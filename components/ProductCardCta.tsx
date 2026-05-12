"use client";

import Link from "next/link";
import { useState } from "react";
import { addItemToCart } from "@/lib/cart-actions";
import { hapticTap } from "@/lib/native/haptics";

type Props = {
  productId: string;
  slug: string;
  name: string;
  price: number;
  imageUrl: string | null;
  weightGram: number;
  stock: number;
  hasVariants: boolean;
};

/**
 * Tombol CTA kecil untuk product card mobile.
 *
 * - `hasVariants` → Link ke halaman detail (user pilih varian di sana).
 * - `stock <= 0` → state disabled "Habis".
 * - default → direct add ke localStorage cart via addItemToCart (tanpa buka
 *   bottom sheet) supaya tap satu kali langsung masuk keranjang — UX paling
 *   ringan untuk produk single-variant.
 *
 * Dirender DI LUAR Link wrapper di ProductCard untuk hindari nested-interactive
 * (button di dalam anchor → invalid HTML + screen reader bingung).
 */
export function ProductCardCta({
  productId,
  slug,
  name,
  price,
  imageUrl,
  weightGram,
  stock,
  hasVariants,
}: Props) {
  const [added, setAdded] = useState(false);
  const outOfStock = stock <= 0;

  if (outOfStock) {
    return (
      <span className="inline-flex h-8 w-full items-center justify-center rounded-full bg-zinc-100 text-xs font-bold text-zinc-400">
        Habis
      </span>
    );
  }

  if (hasVariants) {
    return (
      <Link
        href={`/products/${slug}`}
        className="inline-flex h-8 w-full items-center justify-center rounded-full bg-white text-xs font-bold text-[#1E5FBF] ring-1 ring-[#1E5FBF] transition active:scale-95 hover:bg-[#1E5FBF] hover:text-white"
      >
        Pilih Varian
      </Link>
    );
  }

  function handleAdd(e: React.MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    hapticTap();
    const result = addItemToCart({
      productId,
      slug,
      variantId: null,
      variantLabel: null,
      name,
      price,
      quantity: 1,
      weightGram,
      stock,
      imageUrl,
    });
    if (!result.ok) return;
    setAdded(true);
    setTimeout(() => setAdded(false), 1600);
  }

  return (
    <button
      type="button"
      onClick={handleAdd}
      className={`inline-flex h-8 w-full items-center justify-center gap-1 rounded-full text-xs font-bold text-white transition active:scale-95 ${
        added ? "bg-emerald-600" : "bg-[#1E5FBF] hover:bg-[#174ea0]"
      }`}
      aria-label={added ? "Sudah masuk keranjang" : `Tambah ${name} ke keranjang`}
    >
      {added ? (
        <>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3} className="h-3.5 w-3.5">
            <path d="M5 13l4 4L19 7" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          Masuk
        </>
      ) : (
        <>
          <span className="text-sm leading-none">+</span>
          Keranjang
        </>
      )}
    </button>
  );
}
