import { ProductCardSkeleton, Skeleton } from "@/components/Skeleton";

/**
 * Skeleton grid katalog. Meniru geometri grid asli (2/3/4 kolom) supaya tidak
 * ada lompatan lebar saat data masuk.
 */
export function ProductsGridSkeleton({ withSidebar = false }: { withSidebar?: boolean }) {
  const grid = (
    <div className="grid grid-cols-2 gap-3 sm:gap-5 md:grid-cols-3 lg:grid-cols-4">
      {Array.from({ length: 8 }).map((_, i) => (
        <ProductCardSkeleton key={i} />
      ))}
    </div>
  );

  if (!withSidebar) return grid;

  return (
    <div className="mt-4 gap-6 md:grid md:grid-cols-[248px_1fr]">
      <div className="hidden md:block">
        <div className="space-y-4 rounded-2xl border border-gray-100 bg-white p-4">
          <Skeleton className="h-4 w-16" />
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-8 w-full" />
          ))}
        </div>
      </div>
      <div className="min-w-0">{grid}</div>
    </div>
  );
}
