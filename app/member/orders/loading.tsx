import { Skeleton } from "@/components/Skeleton";

function OrderCardSkeleton() {
  return (
    <article className="rounded-[24px] bg-white px-5 py-4 shadow-[0_4px_20px_-8px_rgba(15,23,42,0.08)] ring-1 ring-slate-100">
      <div className="flex gap-3.5">
        <Skeleton className="h-12 w-12 shrink-0 rounded-xl" />
        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between gap-3">
            <Skeleton className="h-3 w-32 rounded-full" />
            <Skeleton className="h-3 w-24 rounded-full" />
          </div>
          <div className="mt-3 flex items-start justify-between gap-3">
            <div className="min-w-0 flex-1 space-y-2">
              <Skeleton className="h-4 w-full rounded-full" />
              <Skeleton className="h-4 w-2/3 rounded-full" />
            </div>
            <Skeleton className="h-7 w-24 rounded-full" />
          </div>
          <Skeleton className="mt-3 h-3 w-48 rounded-full" />
        </div>
      </div>
      <div className="mt-4 flex items-end justify-between border-t border-dashed border-slate-200 pt-4">
        <div className="space-y-2">
          <Skeleton className="h-3 w-12 rounded-full" />
          <Skeleton className="h-5 w-28 rounded-full" />
        </div>
        <div className="flex gap-2">
          <Skeleton className="h-11 w-20 rounded-full" />
          <Skeleton className="h-11 w-24 rounded-full" />
        </div>
      </div>
    </article>
  );
}

export default function OrdersLoading() {
  return (
    <main
      className="min-h-screen pb-[calc(96px+env(safe-area-inset-bottom))]"
      style={{
        background:
          "radial-gradient(1200px 600px at 10% -10%, #DBEAFE 0%, transparent 60%), radial-gradient(900px 500px at 100% 100%, #E0F2FE 0%, transparent 55%), #F6F7FB",
      }}
    >
      <header className="sticky top-0 z-50 border-b border-slate-200/70 bg-white/90 px-4 py-3 shadow-[0_8px_24px_-20px_rgba(15,23,42,0.4)] backdrop-blur [padding-top:calc(0.75rem+env(safe-area-inset-top))]">
        <div className="mx-auto flex max-w-4xl items-center gap-3">
          <Skeleton className="h-11 w-6" />
          <div className="space-y-2">
            <Skeleton className="h-5 w-40 rounded-full" />
            <Skeleton className="h-3 w-52 rounded-full" />
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-4xl px-4 py-4 md:py-8">
        <Skeleton className="h-12 w-full rounded-2xl" />
        <div className="-mx-4 mt-3 flex gap-2 overflow-hidden px-4 py-1">
          {Array.from({ length: 6 }).map((_, index) => (
            <Skeleton key={index} className="h-11 w-28 shrink-0 rounded-full" />
          ))}
        </div>
        <div className="mt-3 flex justify-between">
          <Skeleton className="h-4 w-32 rounded-full" />
          <Skeleton className="h-10 w-28 rounded-full" />
        </div>
        <div className="mt-4 space-y-4">
          {Array.from({ length: 3 }).map((_, index) => (
            <OrderCardSkeleton key={index} />
          ))}
        </div>
      </div>
    </main>
  );
}
