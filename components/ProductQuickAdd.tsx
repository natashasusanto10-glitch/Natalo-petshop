"use client";

import { useRouter } from "next/navigation";
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
  className?: string;
};

/**
 * Tombol quick-add bulat yang melayang di pojok kanan-bawah gambar kartu
 * produk. Muncul hanya saat kartu di-hover (desktop, media query
 * hover:hover via group-hover Tailwind v4) — di mobile kartu tetap bersih
 * dan pembeli memakai tombol CTA/PDP.
 *
 * - Single-variant + stok ada → direct add ke keranjang (satu klik).
 * - Multi-variant → navigasi ke halaman detail (pilih varian di sana).
 * - Habis → tidak dirender.
 *
 * HARUS dirender DI LUAR <Link> kartu (nested-interactive invalid HTML);
 * ProductCard memposisikannya via container overlay pointer-events-none.
 */
export function ProductQuickAdd({
  productId,
  slug,
  name,
  price,
  imageUrl,
  weightGram,
  stock,
  hasVariants,
  className = "",
}: Props) {
  const router = useRouter();
  const [added, setAdded] = useState(false);

  if (!hasVariants && stock <= 0) return null;

  function handleClick(e: React.MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    hapticTap();

    if (hasVariants) {
      router.push(`/products/${slug}`);
      return;
    }
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
      onClick={handleClick}
      aria-label={
        added
          ? "Sudah masuk keranjang"
          : hasVariants
            ? `Pilih varian ${name}`
            : `Tambah ${name} ke keranjang`
      }
      className={`flex h-10 w-10 items-center justify-center rounded-full border border-black/5 text-[#1E5FBF] shadow-[0_4px_10px_rgba(15,23,42,0.16)] transition-all duration-150 [transition-timing-function:cubic-bezier(0.25,1,0.5,1)] hover:bg-natalo-600 hover:text-white active:scale-90 active:duration-100 ${
        added ? "bg-emerald-600 text-white" : "bg-white"
      } ${className}`}
    >
      {added ? (
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3} className="h-4 w-4">
          <path d="M5 13l4 4L19 7" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      ) : hasVariants ? (
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-4 w-4">
          <path d="M9 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      ) : (
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" className="h-4 w-4">
          <circle cx="8" cy="21" r="1" />
          <circle cx="19" cy="21" r="1" />
          <path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12" />
        </svg>
      )}
    </button>
  );
}
