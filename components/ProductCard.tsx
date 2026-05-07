"use client";

import Image from "next/image";
import Link from "next/link";
import { StoreProduct } from "@/lib/products";
import { formatRupiah } from "@/lib/format";
import { WishlistButton } from "./WishlistButton";

  return (
    <div className="group relative flex flex-col overflow-hidden rounded-2xl bg-gray-50 transition hover:shadow-md">
      <Link href={`/products/${product.slug}`} className="flex flex-1 flex-col">
        {/* Image area */}
        <div className="relative aspect-square bg-gray-100">
          {product.imageUrl ? (
            <Image
              src={product.imageUrl}
              alt={product.name}
              fill
              className="object-cover transition group-hover:scale-105"
            />
          ) : (
            <div className="flex h-full items-center justify-center text-5xl text-gray-300">🐾</div>
          )}
          {product.memberPrice && (
            <span className="absolute left-3 top-3 rounded-full bg-orange-500 px-2 py-0.5 text-xs font-bold text-white">
              Member
            </span>
          )}
        </div>

        {/* Info */}
        <div className="flex flex-1 flex-col p-4">
          <h3 className="font-semibold text-gray-900 leading-snug">{product.name}</h3>
          <p className="mt-1 line-clamp-2 text-xs text-gray-500">{product.description}</p>

          <div className="mt-3">
            <p className="font-bold text-gray-900">
              {formatRupiah(product.memberPrice ?? product.price)}
            </p>
            {product.memberPrice && (
              <p className="text-xs text-gray-400 line-through">{formatRupiah(product.price)}</p>
            )}
          </div>
        </div>
      </Link>

      {/* Wishlist button */}
      <div className="absolute right-3 top-3">
        <WishlistButton product={product} />
      </div>
    </div>
  );
}
