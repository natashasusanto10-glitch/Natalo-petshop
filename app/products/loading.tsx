import { Skeleton } from "@/components/Skeleton";
import { ProductsGridSkeleton } from "@/components/products/ProductsGridSkeleton";

export default function ProductsLoading() {
  return (
    <div className="mx-auto max-w-[var(--nat-container)] px-[var(--nat-gutter)] py-4 md:py-10">
      <div className="mb-5 md:mb-6">
        <Skeleton className="h-7 w-44" />
        <Skeleton className="mt-2 h-3.5 w-56" />
      </div>
      <Skeleton className="mb-3 h-3 w-40" />
      <ProductsGridSkeleton withSidebar />
    </div>
  );
}
