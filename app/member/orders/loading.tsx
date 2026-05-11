import { Skeleton, ListItemSkeleton } from "@/components/Skeleton";

export default function OrdersLoading() {
  return (
    <div className="mx-auto max-w-3xl px-4 py-4 md:py-8">
      <Skeleton className="h-7 w-48" />
      <Skeleton className="mt-2 h-3.5 w-56" />
      <div className="mt-6 space-y-3">
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className="rounded-2xl border border-gray-100 bg-white p-4">
            <div className="flex items-center justify-between">
              <Skeleton className="h-4 w-32" />
              <Skeleton className="h-5 w-16 rounded-full" />
            </div>
            <div className="mt-3 flex gap-3">
              <Skeleton className="h-16 w-16 shrink-0 rounded-lg" />
              <div className="flex-1 space-y-2">
                <Skeleton className="h-4 w-3/4" />
                <Skeleton className="h-3 w-1/2" />
                <Skeleton className="h-5 w-24" />
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
