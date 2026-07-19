import { Skeleton } from "@/components/Skeleton";

export default function KategoriLoading() {
  return (
    <div className="mx-auto max-w-[var(--nat-container)] px-[var(--nat-gutter)] py-4 md:py-8">
      <Skeleton className="h-7 w-48" />
      <Skeleton className="mt-2 h-3.5 w-64" />
      <div className="mt-6 grid grid-cols-3 gap-3 sm:grid-cols-4 lg:grid-cols-6">
        {Array.from({ length: 12 }).map((_, i) => (
          <div key={i} className="flex flex-col items-center gap-2 rounded-2xl border border-gray-100 bg-white p-3">
            <Skeleton variant="circle" className="h-14 w-14" />
            <Skeleton className="h-3 w-16" />
            <Skeleton className="h-3 w-10" />
          </div>
        ))}
      </div>
    </div>
  );
}
