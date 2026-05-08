import Image from "next/image";
import Link from "next/link";
import { StoreProduct } from "@/lib/products";
import { formatRupiah } from "@/lib/format";
import { WishlistButton } from "./WishlistButton";

type Props = {
  product: StoreProduct;
  priority?: boolean;
  isFavorited?: boolean;
  variant?: "default" | "compact";
};

export function ProductCard({
  product,
  priority = false,
  isFavorited: _isFavorited,
  variant = "default",
}: Props) {
  const memberPrice = product.memberPrice ?? null;
  const discountPrice = product.discountPrice ?? null;
  const displayPrice = memberPrice ?? discountPrice ?? product.price;
  const hasMarkdown =
    (memberPrice !== null && memberPrice < product.price) ||
    (discountPrice !== null && discountPrice < product.price);
  const isCompact = variant === "compact";
  const outOfStock = product.stock <= 0;
  const productHref = `/products/${product.slug}`;
  const discountPercent = hasMarkdown
    ? Math.max(1, Math.round(((product.price - displayPrice) / product.price) * 100))
    : 0;

  if (isCompact) {
    return (
      <div className="group relative flex min-w-0 flex-col overflow-hidden rounded-2xl border border-[#f0f0f0] bg-white p-3 transition active:opacity-90 sm:hover:shadow-lg">
        <Link href={productHref} className="flex min-w-0 flex-1 flex-col">
          <div className="relative aspect-square max-h-[160px] w-full overflow-hidden rounded-t-xl bg-gray-100">
            {product.imageUrl ? (
              <Image
                src={product.imageUrl}
                alt={product.name}
                fill
                priority={priority}
                sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 16vw"
                className="object-cover transition group-hover:scale-105"
              />
            ) : (
              <div className="flex h-full items-center justify-center text-4xl text-gray-300">🐾</div>
            )}

            <span
              className={`absolute left-2 top-2 rounded-full px-2 py-0.5 text-[10px] font-bold ${
                outOfStock
                  ? "bg-gray-900/75 text-white"
                  : "bg-emerald-500 text-white"
              }`}
            >
              {outOfStock ? "Habis" : "Tersedia"}
            </span>
          </div>

          <div className="flex min-w-0 flex-1 flex-col pt-3">
            <h3 className="line-clamp-2 min-h-[2.5rem] text-sm font-semibold leading-snug text-[#222]">
              {product.name}
            </h3>

            {product.hasVariants && (
              <div className="mt-2 flex flex-wrap gap-1">
                <span className="rounded-md bg-[#F5F5F5] px-2 py-1 text-[11px] font-semibold text-gray-600">
                  Varian tersedia
                </span>
              </div>
            )}

            <div className="mt-1 flex items-center gap-1 text-[11px] text-gray-500">
              <span className="text-amber-400">★</span>
              <span className="font-semibold text-gray-700">
                {product.avgRating > 0 ? product.avgRating.toFixed(1) : "Baru"}
              </span>
              <span>({product.reviewCount})</span>
            </div>

            <div className="mt-2">
              <p className="text-base font-black leading-tight text-[#E8711F]">
                {formatRupiah(displayPrice)}
              </p>
              {hasMarkdown && (
                <div className="mt-1 flex flex-wrap items-center gap-1.5">
                  <span className="text-xs text-gray-400 line-through">
                    {formatRupiah(product.price)}
                  </span>
                  <span className="rounded-md bg-[#FEE2E2] px-1.5 py-0.5 text-[11px] font-bold text-red-600">
                    {discountPercent}%
                  </span>
                </div>
              )}
            </div>
          </div>
        </Link>

        {/* Wishlist button — outside Link to avoid nested-interactive */}
        <div className="absolute right-5 top-5">
          <WishlistButton
            size="sm"
            product={{
              id: product.id,
              name: product.name,
              slug: product.slug,
              price: product.price,
              memberPrice,
              imageUrl: product.imageUrl,
              weightGram: product.weightGram,
            }}
          />
        </div>
      </div>
    );
  }

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
              priority={priority}
              className="object-cover transition group-hover:scale-105"
            />
          ) : (
            <div className="flex h-full items-center justify-center text-5xl text-gray-300">🐾</div>
          )}
          {memberPrice !== null && (
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
            <p className="font-bold text-gray-900">{formatRupiah(displayPrice)}</p>
            {hasMarkdown && (
              <p className="text-xs text-gray-400 line-through">{formatRupiah(product.price)}</p>
            )}
          </div>
        </div>
      </Link>

      {/* Wishlist button */}
      <div className="absolute right-3 top-3">
        <WishlistButton
          product={{
            id: product.id,
            name: product.name,
            slug: product.slug,
            price: product.price,
            memberPrice,
            imageUrl: product.imageUrl,
            weightGram: product.weightGram,
          }}
        />
      </div>
    </div>
  );
}
