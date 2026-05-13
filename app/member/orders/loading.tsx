import { Skeleton } from "@/components/Skeleton";

export default function OrdersLoading() {
  return (
    <main className="min-h-screen bg-zinc-50 pb-[calc(2rem+env(safe-area-inset-bottom))]">
      <header className="sticky top-0 z-50 border-b border-zinc-100 bg-white px-4 pb-3 pt-3 shadow-sm [padding-top:calc(0.75rem+env(safe-area-inset-top))]">
        <div className="mx-auto flex max-w-4xl items-center gap-2">
          <Skeleton className="h-10 w-10 rounded-full" />
          <Skeleton className="h-7 w-44" />
        </div>
      </header>
      <div className="mx-auto max-w-4xl px-4 py-4 md:py-8">
        <div className="-mx-4 flex gap-2 overflow-hidden px-4 pb-2">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-9 w-24 shrink-0 rounded-full" />
          ))}
        </div>
        <div className="mt-3 space-y-4">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="rounded-2xl border border-zinc-100 bg-white p-4">
              <div className="flex items-center justify-between">
                <Skeleton className="h-4 w-36" />
                <Skeleton className="h-6 w-24 rounded-full" />
              </div>
              <div className="mt-4 space-y-2">
                <Skeleton className="h-4 w-3/4" />
                <Skeleton className="h-4 w-1/2" />
              </div>
              <div className="mt-4 flex items-center justify-between border-t border-zinc-100 pt-4">
                <Skeleton className="h-4 w-28" />
                <Skeleton className="h-9 w-32 rounded-full" />
              </div>
            </div>
          ))}
        </div>
      </div>
    </main>
  );
}
