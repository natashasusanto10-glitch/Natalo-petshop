import { Skeleton, MemberCardSkeleton, ListItemSkeleton } from "@/components/Skeleton";

export default function MemberLoading() {
  return (
    <div className="mx-auto max-w-3xl px-4 py-4 md:py-8 space-y-4">
      <MemberCardSkeleton />

      <div className="rounded-2xl border border-blue-100 bg-blue-50 p-5">
        <Skeleton className="h-5 w-32" />
        <div className="mt-4 space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <ListItemSkeleton key={i} />
          ))}
        </div>
      </div>

      <div className="rounded-2xl border border-gray-100 bg-white p-5">
        <Skeleton className="h-5 w-40" />
        <div className="mt-4 grid grid-cols-2 gap-3">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-20 rounded-xl" />
          ))}
        </div>
      </div>
    </div>
  );
}
