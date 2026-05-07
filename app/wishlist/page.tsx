"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { formatRupiah } from "@/lib/format";
import { getWishlistItems, WishlistButton } from "@/components/WishlistButton";

type WishlistItem = {
  id: string;
  name: string;
  slug: string;
  price: number;
  memberPrice?: number | null;
  imageUrl: string | null;
  weightGram?: number;
};

function addToCart(item: WishlistItem) {
  try {
    const cart: { productId: string; name: string; price: number; quantity: number; weightGram: number; imageUrl?: string | null }[] =
      JSON.parse(localStorage.getItem("cart") ?? "[]");
    const price = item.memberPrice ?? item.price;
    const existing = cart.find((c) => c.productId === item.id);
    if (existing) {
      existing.quantity += 1;
    } else {
      cart.push({
        productId: item.id,
        name: item.name,
        price,
        quantity: 1,
        weightGram: item.weightGram ?? 500,
        imageUrl: item.imageUrl,
      });
    }
    localStorage.setItem("cart", JSON.stringify(cart));
    window.dispatchEvent(new Event("cart-updated"));
  } catch {}
}

export default function WishlistPage() {
  const [items, setItems] = useState<WishlistItem[]>([]);
  const [addedIds, setAddedIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    function sync() { setItems(getWishlistItems()); }
    sync();
    window.addEventListener("wishlist-updated", sync);
    return () => window.removeEventListener("wishlist-updated", sync);
  }, []);

  function handleAddToCart(item: WishlistItem) {
    addToCart(item);
    setAddedIds((prev) => new Set(prev).add(item.id));
    setTimeout(() => {
      setAddedIds((prev) => { const s = new Set(prev); s.delete(item.id); return s; });
    }, 2000);
  }

  return (
    <div className="mx-auto max-w-4xl px-4 py-4 md:py-10">
      <h1 className="text-2xl font-black text-gray-900 md:text-3xl">Wishlist</h1>
      <p className="mt-1 text-sm text-gray-500">{items.length} produk disimpan</p>

      {items.length === 0 ? (
        <div className="mt-10 rounded-3xl border border-dashed border-gray-200 p-16 text-center">
          <span className="text-6xl">🤍</span>
          <p className="mt-4 font-semibold text-gray-500">Wishlist kamu masih kosong.</p>
          <Link
            href="/products"
            className="mt-5 inline-flex rounded-full bg-orange-500 px-7 py-3 text-sm font-bold text-white transition hover:bg-orange-600"
          >
            Jelajahi Produk
          </Link>
        </div>
      ) : (
        <>
          <div className="mt-6 grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-3">
            {items.map((item) => (
              <div key={item.id} className="group relative flex flex-col rounded-2xl border border-gray-100 bg-white shadow-sm overflow-hidden">
                <Link href={`/products/${item.slug}`}>
                  <div className="relative aspect-square bg-gray-100">
                    {item.imageUrl ? (
                      <Image src={item.imageUrl} alt={item.name} fill className="object-cover transition group-hover:scale-105" />
                    ) : (
                      <div className="flex h-full items-center justify-center text-5xl text-gray-300">🐾</div>
                    )}
                  </div>
                  <div className="p-4">
                    <p className="font-semibold text-gray-900 leading-snug">{item.name}</p>
                    <div className="mt-2 flex items-center gap-2">
                      <p className="font-bold text-gray-900">{formatRupiah(item.memberPrice ?? item.price)}</p>
                      {item.memberPrice && (
                        <p className="text-xs text-gray-400 line-through">{formatRupiah(item.price)}</p>
                      )}
                    </div>
                  </div>
                </Link>

                {/* Wishlist remove button */}
                <div className="absolute right-3 top-3">
                  <WishlistButton product={item} />
                </div>

                {/* Actions */}
                <div className="mt-auto grid grid-cols-2 gap-2 px-4 pb-4">
                  <Link
                    href={`/products/${item.slug}`}
                    className="flex items-center justify-center rounded-full border border-gray-200 py-2.5 text-xs font-bold text-gray-700 transition hover:border-orange-400 hover:text-orange-500"
                  >
                    Lihat Produk
                  </Link>
                  <button
                    onClick={() => handleAddToCart(item)}
                    className={`flex items-center justify-center rounded-full py-2.5 text-xs font-bold text-white transition ${
                      addedIds.has(item.id) ? "bg-green-500" : "bg-orange-500 hover:bg-orange-600"
                    }`}
                  >
                    {addedIds.has(item.id) ? "✓ Ditambahkan" : "+ Keranjang"}
                  </button>
                </div>
              </div>
            ))}
          </div>

          {/* Quick checkout link */}
          <div className="mt-8 flex justify-end">
            <Link
              href="/cart"
              className="rounded-full bg-orange-500 px-7 py-3 text-sm font-bold text-white transition hover:bg-orange-600"
            >
              Lihat Keranjang →
            </Link>
          </div>
        </>
      )}
    </div>
  );
}
