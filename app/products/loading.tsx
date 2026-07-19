import { Skeleton, ProductCardSkeleton } from "@/components/Skeleton";

export default function ProductsLoading() {
  return (
    <div className="mx-auto max-w-[var(--nat-container)] px-[var(--nat-gutter)] py-4 md:py-10">
      <div className="mb-5 md:mb-6">
        <Skeleton className="h-7 w-44" />
        <Skeleton className="mt-2 h-3.5 w-56" />
      </div>
      <div className="mb-5 flex gap-2 overflow-hidden md:mb-6">
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} className="h-9 w-24 shrink-0 rounded-full" />
        ))}
      </div>
      <Skeleton className="mb-3 h-3 w-40" />
      <div className="grid grid-cols-2 gap-3 sm:gap-5 md:grid-cols-3 lg:grid-cols-4">
        {Array.from({ length: 8 }).map((_, i) => (
          <ProductCardSkeleton key={i} />
        ))}
      </div>
    </div>
  );
}
