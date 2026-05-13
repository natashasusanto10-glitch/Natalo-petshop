import Image from "next/image";
import Link from "next/link";
import type { StoreProduct } from "@/lib/products";
import { formatRupiah } from "@/lib/format";
import { IMAGE_BLUR_GRAY } from "@/lib/image-placeholder";

type HomeProductCardProps = {
  product: StoreProduct;
  badge?: "Baru" | "Original" | "Promo" | "Terlaris";
  priority?: boolean;
};

export function HomeProductCard({
  product,
  badge,
  priority = false,
}: HomeProductCardProps) {
  const displayPrice = product.memberPrice ?? product.discountPrice ?? product.price;
  const hasMarkdown = displayPrice < product.price;

  return (
    <Link
      href={`/products/${product.slug}`}
      className="group flex min-w-0 flex-col overflow-hidden rounded-[18px] border border-[#e8eef7] bg-white p-2.5 shadow-[0_6px_18px_rgba(15,23,42,0.05)] transition active:scale-[0.99] active:opacity-90 sm:p-3 sm:hover:-translate-y-0.5 sm:hover:shadow-[0_12px_28px_rgba(15,23,42,0.08)]"
    >
      <div
        className="relative aspect-square w-full rounded-2xl bg-white"
        style={{ viewTransitionName: `nat-home-prod-${product.slug}` }}
      >
        {product.imageUrl ? (
          <Image
            src={product.imageUrl}
            alt={product.name}
            fill
            {...(priority ? { priority: true } : { loading: "lazy" as const })}
            sizes="(max-width: 640px) 50vw, (max-width: 1024px) 33vw, 220px"
            placeholder="blur"
            blurDataURL={IMAGE_BLUR_GRAY}
            className="object-contain p-2 transition duration-200 group-hover:scale-[1.03]"
          />
        ) : (
          <div className="flex h-full items-center justify-center text-4xl text-zinc-200">
            Produk
          </div>
        )}

        {badge && (
          <span className="absolute left-1.5 top-1.5 rounded-full border border-white/80 bg-white/95 px-2 py-0.5 text-[10px] font-black text-[#1E5FBF] shadow-sm">
            {badge}
          </span>
        )}
      </div>

      <div className="flex min-w-0 flex-1 flex-col px-0.5 pb-0.5 pt-2">
        <h3 className="line-clamp-2 min-h-[2.35rem] text-[12px] font-bold leading-snug text-zinc-800 sm:text-sm">
          {product.name}
        </h3>

        <div className="mt-2">
          <p className="truncate text-[14px] font-black leading-tight text-[#1E5FBF] sm:text-base">
            {formatRupiah(displayPrice)}
          </p>
          {hasMarkdown && (
            <p className="mt-0.5 truncate text-[11px] font-medium text-zinc-400 line-through">
              {formatRupiah(product.price)}
            </p>
          )}
        </div>

        {(product.avgRating > 0 || product.reviewCount > 0) && (
          <p className="mt-1.5 truncate text-[11px] font-semibold text-zinc-500">
            {product.avgRating > 0 ? `Rating ${product.avgRating.toFixed(1)}` : "Baru"}
            {product.reviewCount > 0 ? ` - ${product.reviewCount} ulasan` : ""}
          </p>
        )}
      </div>
    </Link>
  );
}

export function HomeProductSkeleton({ count = 4 }: { count?: number }) {
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
      {Array.from({ length: count }).map((_, index) => (
        <div
          key={index}
          className="overflow-hidden rounded-[18px] border border-[#e8eef7] bg-white p-2.5 shadow-[0_6px_18px_rgba(15,23,42,0.05)]"
        >
          <div className="aspect-square animate-pulse rounded-2xl bg-zinc-100" />
          <div className="space-y-2 px-0.5 pb-0.5 pt-3">
            <div className="h-3.5 w-full animate-pulse rounded-full bg-zinc-100" />
            <div className="h-3.5 w-2/3 animate-pulse rounded-full bg-zinc-100" />
            <div className="h-4 w-1/2 animate-pulse rounded-full bg-zinc-100" />
          </div>
        </div>
      ))}
    </div>
  );
}
