"use client";

import { useEffect, useState } from "react";

type WishlistItem = {
  id: string;
  name: string;
  slug: string;
  price: number;
  memberPrice?: number | null;
  imageUrl: string | null;
  weightGram?: number;
  stock?: number | null;
  hasVariants?: boolean;
};

function getWishlist(): string[] {
  if (typeof window === "undefined") return [];
  try {
    return JSON.parse(localStorage.getItem("wishlist") ?? "[]");
  } catch {
    return [];
  }
}

function getWishlistItems(): WishlistItem[] {
  if (typeof window === "undefined") return [];
  try {
    return JSON.parse(localStorage.getItem("wishlist-items") ?? "[]");
  } catch {
    return [];
  }
}

export function saveToWishlist(product: WishlistItem) {
  const ids = getWishlist();
  const items = getWishlistItems();
  if (!ids.includes(product.id)) {
    localStorage.setItem("wishlist", JSON.stringify([...ids, product.id]));
    localStorage.setItem("wishlist-items", JSON.stringify([...items, product]));
  } else {
    localStorage.setItem("wishlist", JSON.stringify(ids.filter((i) => i !== product.id)));
    localStorage.setItem("wishlist-items", JSON.stringify(items.filter((i) => i.id !== product.id)));
  }
  window.dispatchEvent(new Event("wishlist-updated"));
}

export function WishlistButton({
  product,
  size = "md",
}: {
  product: WishlistItem;
  size?: "sm" | "md";
}) {
  const [saved, setSaved] = useState(false);
  const sizeClass = size === "sm" ? "h-7 w-7" : "h-9 w-9";
  const iconClass = size === "sm" ? "h-3.5 w-3.5" : "h-4 w-4";

  useEffect(() => {
    function sync() {
      setSaved(getWishlist().includes(product.id));
    }
    sync();
    window.addEventListener("wishlist-updated", sync);
    return () => window.removeEventListener("wishlist-updated", sync);
  }, [product.id]);

  return (
    <button
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        saveToWishlist(product);
      }}
      aria-label={saved ? "Hapus dari wishlist" : "Simpan ke wishlist"}
      className={`flex ${sizeClass} items-center justify-center rounded-full border transition ${
        saved
          ? "border-red-300 bg-red-50 text-red-500"
          : "border-gray-200 bg-white text-gray-400 hover:border-red-300 hover:text-red-400"
      }`}
    >
      <svg viewBox="0 0 24 24" fill={saved ? "currentColor" : "none"} stroke="currentColor" strokeWidth={1.8} className={iconClass}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12Z" />
      </svg>
    </button>
  );
}

export function WishlistCount() {
  const [count, setCount] = useState(0);
  useEffect(() => {
    function sync() { setCount(getWishlist().length); }
    sync();
    window.addEventListener("wishlist-updated", sync);
    return () => window.removeEventListener("wishlist-updated", sync);
  }, []);
  return count > 0 ? (
    <span className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-red-500 text-[10px] font-bold text-white">
      {count > 9 ? "9+" : count}
    </span>
  ) : null;
}

export { getWishlistItems };
