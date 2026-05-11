import { Skeleton } from "@/components/Skeleton";

export default function BlogLoading() {
  return (
    <div className="mx-auto max-w-4xl px-4 py-4 md:py-10">
      <Skeleton className="h-8 w-56" />
      <Skeleton className="mt-2 h-4 w-72" />
      <div className="mt-8 grid gap-6 sm:grid-cols-2">
        {Array.from({ length: 6 }).map((_, i) => (
          <article key={i} className="overflow-hidden rounded-2xl border border-gray-100 bg-white">
            <Skeleton className="aspect-[16/9] w-full" />
            <div className="space-y-2 p-4">
              <Skeleton className="h-3 w-24" />
              <Skeleton className="h-5 w-full" />
              <Skeleton className="h-5 w-4/5" />
              <Skeleton className="mt-2 h-3 w-full" />
              <Skeleton className="h-3 w-3/4" />
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
