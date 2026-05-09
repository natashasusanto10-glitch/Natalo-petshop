"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { formatRupiah } from "@/lib/format";
import { addItemToCart } from "@/lib/cart-actions";
import { getWishlistItems, WishlistButton } from "@/components/WishlistButton";

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

function currentPrice(item: WishlistItem) {
  return item.memberPrice ?? item.price;
}

function isOutOfStock(item: WishlistItem) {
  return item.stock !== undefined && item.stock !== null && item.stock <= 0;
}

function cartPayload(item: WishlistItem) {
  const price = currentPrice(item);
  return {
    productId: item.id,
    variantId: null,
    variantLabel: null,
    name: item.name,
    price,
    quantity: 1,
    subtotal: price,
    weightGram: item.weightGram ?? 500,
    stock: item.stock ?? null,
    imageUrl: item.imageUrl,
  };
}

export default function WishlistPage() {
  const router = useRouter();
  const [items, setItems] = useState<WishlistItem[]>([]);
  const [addedIds, setAddedIds] = useState<Set<string>>(new Set());
  const [variantItem, setVariantItem] = useState<WishlistItem | null>(null);

  useEffect(() => {
    function sync() {
      setItems(getWishlistItems());
    }
    sync();
    window.addEventListener("wishlist-updated", sync);
    return () => window.removeEventListener("wishlist-updated", sync);
  }, []);

  function handleAddToCart(item: WishlistItem) {
    if (isOutOfStock(item)) return;
    if (item.hasVariants) {
      setVariantItem(item);
      return;
    }

    const result = addItemToCart(cartPayload(item), {
      successMessage: "Produk berhasil ditambahkan ke keranjang",
    });

    if (result.ok) {
      setAddedIds((prev) => new Set(prev).add(item.id));
      setTimeout(() => {
        setAddedIds((prev) => {
          const next = new Set(prev);
          next.delete(item.id);
          return next;
        });
      }, 1800);
    }
  }

  function handleBuyNow(item: WishlistItem) {
    if (isOutOfStock(item)) return;
    if (item.hasVariants) {
      setVariantItem(item);
      return;
    }

    const result = addItemToCart(cartPayload(item), { showToast: false });
    if (result.ok) router.push("/checkout");
  }

  return (
    <div className="mx-auto max-w-4xl px-3 py-4 pb-36 md:px-4 md:py-10 md:pb-10">
      <div className="flex items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-black text-gray-900 md:text-3xl">Wishlist</h1>
          <p className="mt-0.5 text-xs font-semibold text-gray-500 md:text-sm">
            {items.length} produk disimpan
          </p>
        </div>
        {items.length > 0 && (
          <Link href="/products" className="text-xs font-extrabold text-natalo-600">
            Belanja Lagi
          </Link>
        )}
      </div>

      {items.length === 0 ? (
        <div className="mt-8 rounded-2xl border border-dashed border-gray-200 bg-white p-8 text-center md:p-16">
          <p className="text-4xl font-black text-gray-200">NP</p>
          <p className="mt-4 font-semibold text-gray-500">Wishlist kamu masih kosong.</p>
          <Link
            href="/products"
            className="mt-5 inline-flex rounded-xl bg-natalo-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-natalo-700"
          >
            Jelajahi Produk
          </Link>
        </div>
      ) : (
        <div className="mt-4 grid grid-cols-2 gap-2.5 sm:gap-4 lg:grid-cols-3">
          {items.map((item) => {
            const outOfStock = isOutOfStock(item);
            const added = addedIds.has(item.id);
            return (
              <article
                key={item.id}
                className="group relative flex min-w-0 flex-col overflow-hidden rounded-xl border border-gray-100 bg-white shadow-sm"
              >
                <Link href={`/products/${item.slug}`} className="block">
                  <div className="relative aspect-square overflow-hidden bg-gray-100">
                    {item.imageUrl ? (
                      <Image
                        src={item.imageUrl}
                        alt={item.name}
                        fill
                        sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 220px"
                        className="object-cover transition group-hover:scale-105"
                      />
                    ) : (
                      <div className="flex h-full items-center justify-center text-3xl font-black text-gray-200">
                        NP
                      </div>
                    )}
                  </div>
                </Link>

                <div className="absolute right-2 top-2">
                  <WishlistButton product={item} size="sm" />
                </div>

                <div className="flex flex-1 flex-col p-2.5">
                  <Link href={`/products/${item.slug}`} className="min-w-0">
                    <h2 className="line-clamp-2 min-h-[2.35rem] text-[13px] font-bold leading-snug text-gray-900">
                      {item.name}
                    </h2>
                  </Link>

                  <div className="mt-1.5">
                    <p className="truncate text-sm font-black leading-tight text-natalo-600">
                      {formatRupiah(currentPrice(item))}
                    </p>
                    {item.memberPrice !== null && item.memberPrice !== undefined && item.memberPrice < item.price && (
                      <p className="mt-0.5 truncate text-[11px] text-gray-400 line-through">
                        {formatRupiah(item.price)}
                      </p>
                    )}
                  </div>

                  <div className="mt-2 grid grid-cols-2 gap-1.5">
                    <button
                      type="button"
                      onClick={() => handleAddToCart(item)}
                      disabled={outOfStock}
                      className="flex h-9 items-center justify-center rounded-lg border border-natalo-300 px-1 text-[10px] font-extrabold text-natalo-600 transition active:bg-natalo-50 disabled:cursor-not-allowed disabled:border-gray-200 disabled:text-gray-300 xs:text-[11px]"
                    >
                      <span className="whitespace-nowrap">{added ? "Masuk" : "Keranjang"}</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => handleBuyNow(item)}
                      disabled={outOfStock}
                      className="flex h-9 items-center justify-center rounded-lg bg-natalo-600 px-1 text-[10px] font-extrabold text-white transition active:opacity-90 disabled:cursor-not-allowed disabled:bg-gray-300 xs:text-[11px]"
                    >
                      <span className="whitespace-nowrap">{outOfStock ? "Stok Habis" : "Beli Sekarang"}</span>
                    </button>
                  </div>
                </div>
              </article>
            );
          })}
        </div>
      )}

      {variantItem && (
        <div className="fixed inset-0 z-[70] flex items-end bg-black/35 px-3 pb-[calc(86px+env(safe-area-inset-bottom))] md:hidden">
          <div className="w-full rounded-2xl bg-white p-4 shadow-xl">
            <div className="flex gap-3">
              <div className="relative h-16 w-16 shrink-0 overflow-hidden rounded-xl bg-gray-100">
                {variantItem.imageUrl ? (
                  <Image src={variantItem.imageUrl} alt={variantItem.name} fill className="object-cover" />
                ) : (
                  <div className="flex h-full items-center justify-center text-sm font-black text-gray-300">
                    NP
                  </div>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <p className="line-clamp-2 text-sm font-extrabold text-gray-900">{variantItem.name}</p>
                <p className="mt-1 text-sm font-black text-natalo-600">
                  {formatRupiah(currentPrice(variantItem))}
                </p>
              </div>
            </div>
            <p className="mt-3 text-sm leading-6 text-gray-600">
              Produk ini punya pilihan varian. Pilih varian terlebih dahulu agar checkout sesuai.
            </p>
            <div className="mt-4 grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setVariantItem(null)}
                className="h-11 rounded-xl border border-gray-200 text-sm font-extrabold text-gray-700"
              >
                Nanti
              </button>
              <button
                type="button"
                onClick={() => router.push(`/products/${variantItem.slug}`)}
                className="h-11 rounded-xl bg-natalo-600 text-sm font-extrabold text-white"
              >
                Pilih Varian
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
