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
  memberPrice: number | null;
  imageUrl: string | null;
};

export default function WishlistPage() {
  const [items, setItems] = useState<WishlistItem[]>([]);

  useEffect(() => {
    function sync() { setItems(getWishlistItems()); }
    sync();
    window.addEventListener("wishlist-updated", sync);
    return () => window.removeEventListener("wishlist-updated", sync);
  }, []);

  return (
    <div className="mx-auto max-w-4xl px-4 py-10">
      <h1 className="text-3xl font-black text-gray-900">Wishlist</h1>
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
        <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {items.map((item) => (
            <div key={item.id} className="group relative rounded-2xl border border-gray-100 bg-white shadow-sm overflow-hidden">
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
              <div className="absolute right-3 top-3">
                <WishlistButton product={item} />
              </div>
              <div className="px-4 pb-4">
                <Link
                  href={`/products/${item.slug}`}
                  className="flex w-full items-center justify-center rounded-full bg-orange-500 py-2.5 text-sm font-bold text-white transition hover:bg-orange-600"
                >
                  Lihat Produk
                </Link>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
