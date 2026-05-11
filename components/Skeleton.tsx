import type { CSSProperties, HTMLAttributes } from "react";

/**
 * Reusable skeleton component dengan shimmer gradient animation.
 * Lebih smooth dari Tailwind animate-pulse (yang cuma opacity flicker).
 *
 * Usage:
 *   <Skeleton className="h-4 w-32" />
 *   <Skeleton variant="circle" className="h-12 w-12" />
 *   <Skeleton variant="text" lines={3} />
 *
 * Shimmer keyframe ada di app/globals.css (nat-shimmer animation).
 */

type SkeletonVariant = "block" | "circle" | "text";

type SkeletonProps = HTMLAttributes<HTMLDivElement> & {
  variant?: SkeletonVariant;
  /** Untuk variant="text" — jumlah baris yang di-render. Default 1. */
  lines?: number;
};

const baseClasses = "relative overflow-hidden bg-gray-200/70";
const shimmerStyle: CSSProperties = {
  backgroundImage:
    "linear-gradient(90deg, rgba(255,255,255,0) 0%, rgba(255,255,255,0.55) 50%, rgba(255,255,255,0) 100%)",
  backgroundSize: "200% 100%",
  animation: "nat-shimmer 1.4s infinite linear",
};

export function Skeleton({
  variant = "block",
  lines = 1,
  className = "",
  ...rest
}: SkeletonProps) {
  if (variant === "text" && lines > 1) {
    return (
      <div className="space-y-2">
        {Array.from({ length: lines }).map((_, i) => (
          <div
            key={i}
            className={`${baseClasses} rounded-md ${i === lines - 1 ? "w-3/4" : "w-full"} h-3 ${className}`}
          >
            <div className="absolute inset-0" style={shimmerStyle} />
          </div>
        ))}
      </div>
    );
  }

  const radius =
    variant === "circle" ? "rounded-full" : variant === "text" ? "rounded-md" : "rounded-lg";

  return (
    <div className={`${baseClasses} ${radius} ${className}`} {...rest}>
      <div className="absolute inset-0" style={shimmerStyle} />
    </div>
  );
}

/** Product card skeleton — for product list grids. */
export function ProductCardSkeleton() {
  return (
    <div className="overflow-hidden rounded-2xl border border-gray-100 bg-white">
      <Skeleton className="aspect-square w-full" />
      <div className="space-y-2 p-3 md:p-4">
        <Skeleton variant="text" className="h-4 w-3/4" />
        <Skeleton variant="text" className="h-3 w-1/2" />
        <Skeleton variant="text" className="mt-3 h-5 w-1/3" />
      </div>
    </div>
  );
}

/** Order/list item skeleton — for orders, vouchers, etc. */
export function ListItemSkeleton() {
  return (
    <div className="flex items-center gap-3 rounded-2xl border border-gray-100 bg-white p-4">
      <Skeleton variant="circle" className="h-12 w-12 shrink-0" />
      <div className="min-w-0 flex-1 space-y-2">
        <Skeleton variant="text" className="h-4 w-3/4" />
        <Skeleton variant="text" className="h-3 w-1/2" />
      </div>
      <Skeleton className="h-6 w-16 shrink-0" />
    </div>
  );
}

/** Cart item skeleton — for cart page. */
export function CartItemSkeleton() {
  return (
    <div className="flex gap-3 rounded-2xl border border-gray-100 bg-white p-3">
      <Skeleton className="aspect-square h-20 w-20 shrink-0" />
      <div className="min-w-0 flex-1 space-y-2">
        <Skeleton variant="text" className="h-4 w-3/4" />
        <Skeleton variant="text" className="h-3 w-1/3" />
        <div className="flex items-center justify-between pt-2">
          <Skeleton className="h-5 w-20" />
          <Skeleton className="h-7 w-24 rounded-full" />
        </div>
      </div>
    </div>
  );
}

/** Hero / banner skeleton — for top of page. */
export function HeroSkeleton() {
  return <Skeleton className="aspect-[16/9] w-full rounded-2xl" />;
}

/** Member card skeleton — for member dashboard. */
export function MemberCardSkeleton() {
  return (
    <div className="rounded-3xl bg-gradient-to-br from-natalo-50 via-white to-natalo-50 p-5 md:p-8">
      <div className="flex items-center gap-4">
        <Skeleton variant="circle" className="h-16 w-16" />
        <div className="flex-1 space-y-2">
          <Skeleton variant="text" className="h-5 w-32" />
          <Skeleton variant="text" className="h-3 w-48" />
        </div>
      </div>
      <div className="mt-5 grid grid-cols-3 gap-3">
        {[1, 2, 3].map((i) => (
          <div key={i} className="space-y-2">
            <Skeleton className="h-5 w-14" />
            <Skeleton className="h-3 w-20" />
          </div>
        ))}
      </div>
    </div>
  );
}
