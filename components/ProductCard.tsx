import Image from "next/image";
import Link from "next/link";
import { StoreProduct } from "@/lib/products";
import { formatRupiah } from "@/lib/format";
import { FavoriteButton } from "@/components/FavoriteButton";
import { QuickAddToCart } from "@/components/QuickAddToCart";
import { Stars } from "@/components/StarRating";

export function ProductCard({
  product,
  priority = false,
  isFavorited = false,
}: {
  product: StoreProduct;
  priority?: boolean;
  isFavorited?: boolean;
}) {
  const hasDiscount =
    product.discountPrice !== null && product.discountPrice < product.price;
  const displayPrice = hasDiscount ? product.discountPrice! : product.price;
  const outOfStock = product.stock <= 0;

  return (
    <article className="group flex h-full flex-col overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm transition hover:shadow-md">
      <div className="relative aspect-square bg-gray-100">
        <Link
          href={`/products/${product.slug}`}
          aria-label={product.name}
          className="block h-full"
        >
          {product.imageUrl ? (
            <Image
              src={product.imageUrl}
              alt={product.name}
              fill
              sizes="(min-width: 1280px) 25vw, (min-width: 1024px) 33vw, (min-width: 640px) 50vw, 100vw"
              priority={priority}
              className="object-cover transition group-hover:scale-105"
            />
          ) : (
            <div className="flex h-full items-center justify-center text-5xl text-gray-300">
              🐾
            </div>
          )}
        </Link>

        {hasDiscount && (
          <span className="absolute left-3 top-3 rounded-full bg-red-500 px-2 py-0.5 text-xs font-bold text-white">
            Diskon
          </span>
        )}

        <span
          className={`absolute bottom-3 left-3 rounded-full px-2 py-0.5 text-xs font-bold ${
            outOfStock
              ? "bg-zinc-700 text-white"
              : "bg-emerald-100 text-emerald-700"
          }`}
        >
          {outOfStock ? "Stok Habis" : "Tersedia"}
        </span>

        <div className="absolute right-2 top-2">
          <FavoriteButton productId={product.id} initialFavorited={isFavorited} />
        </div>
      </div>

      <div className="flex flex-1 flex-col p-4">
        <Link href={`/products/${product.slug}`} className="block">
          <h3 className="min-h-[2.75rem] overflow-hidden font-semibold leading-snug text-gray-900 transition [display:-webkit-box] [-webkit-box-orient:vertical] [-webkit-line-clamp:2] group-hover:text-natalo-700">
            {product.name}
          </h3>
        </Link>

        <div className="mt-3 min-h-[2.25rem]">
          <p className="font-bold text-natalo-700">
            {formatRupiah(displayPrice)}
          </p>
          {hasDiscount && (
            <p className="text-xs text-gray-400 line-through">
              {formatRupiah(product.price)}
            </p>
          )}
        </div>

        {product.reviewCount > 0 ? (
          <div className="mt-2">
            <Stars
              rating={product.avgRating}
              size="xs"
              showValue
              count={product.reviewCount}
            />
          </div>
        ) : (
          <p className="mt-2 text-[11px] text-gray-300">Belum ada review</p>
        )}

        <div className="mt-auto grid grid-cols-[1fr_1.15fr] gap-2 pt-4">
          <Link
            href={`/products/${product.slug}`}
            className="flex items-center justify-center rounded-full border border-gray-200 px-3 py-2 text-xs font-bold text-gray-700 transition hover:border-natalo-300 hover:text-natalo-700"
          >
            Detail
          </Link>
          <QuickAddToCart
            product={{
              id: product.id,
              slug: product.slug,
              name: product.name,
              price: product.price,
              discountPrice: product.discountPrice,
              stock: product.stock,
              weightGram: product.weightGram,
              imageUrl: product.imageUrl,
              isActive: true,
              hasVariants: product.hasVariants,
            }}
            className="py-2"
          />
        </div>
      </div>
    </article>
  );
}
