import type { StoreProduct } from "@/lib/products";
import { ProductCard } from "@/components/ProductCard";
import { Skeleton } from "@/components/Skeleton";

type HomeProductCardProps = {
  product: StoreProduct;
  badge?: "Baru" | "Original" | "Promo" | "Terlaris";
  priority?: boolean;
  rankBadge?: number;
};

export function HomeProductCard({
  product,
  badge,
  priority = false,
  rankBadge,
}: HomeProductCardProps) {
  return (
    <ProductCard
      product={product}
      badge={badge}
      priority={priority}
      showCta={false}
      showRating
      rankBadge={rankBadge}
    />
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
          {/* Skeleton shimmer (nat-shimmer) — konsisten dgn Skeleton.tsx,
              bukan animate-pulse (opacity flicker terasa kaku). */}
          <Skeleton className="aspect-square rounded-2xl" />
          <div className="space-y-2 px-0.5 pb-0.5 pt-3">
            <Skeleton variant="text" className="h-3.5 w-full" />
            <Skeleton variant="text" className="h-3.5 w-2/3" />
            <Skeleton className="h-4 w-1/2" />
          </div>
        </div>
      ))}
    </div>
  );
}
