import Image from "next/image";
import Link from "next/link";
import { StoreProduct } from "@/lib/products";
import { formatRupiah } from "@/lib/format";

export function ProductCard({ product }: { product: StoreProduct }) {
  return (
    <Link
      href={`/products/${product.slug}`}
      className="group flex flex-col overflow-hidden rounded-2xl bg-gray-50 transition hover:shadow-md"
    >
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

        <div className="mt-3 flex items-center justify-between gap-2">
          <div>
            <p className="font-bold text-gray-900">
              {formatRupiah(product.memberPrice ?? product.price)}
            </p>
            {product.memberPrice && (
              <p className="text-xs text-gray-400 line-through">{formatRupiah(product.price)}</p>
            )}
          </div>
          {/* Heart icon */}
          <svg
            className="h-5 w-5 text-orange-400 transition group-hover:text-orange-500"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            strokeWidth={1.8}
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12Z"
            />
          </svg>
        </div>
      </div>
    </Link>
  );
}
