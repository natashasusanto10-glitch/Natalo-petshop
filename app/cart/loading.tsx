export default function CartLoading() {
  return (
    <div className="mx-auto max-w-3xl px-4 py-4 pb-[calc(150px+env(safe-area-inset-bottom))] md:py-10 md:pb-10">
      <div className="flex items-start justify-between gap-4">
        <div className="space-y-2">
          <div className="h-7 w-40 animate-pulse rounded-lg bg-gray-100 md:h-8 md:w-48" />
          <div className="h-4 w-44 animate-pulse rounded bg-gray-100" />
        </div>
        <div className="h-10 w-24 animate-pulse rounded-full bg-gray-100" />
      </div>

      <section className="mt-4 overflow-hidden rounded-2xl border border-gray-100 bg-white md:mt-8">
        <div className="flex items-center justify-between gap-3 border-b border-gray-100 px-4 py-3">
          <div className="h-5 w-28 animate-pulse rounded bg-gray-100" />
          <div className="h-4 w-12 animate-pulse rounded bg-gray-100" />
        </div>

        {/* Voucher claim bar */}
        <div className="px-4 py-3">
          <div className="h-12 animate-pulse rounded-xl bg-gray-100" />
        </div>

        {/* Cart item rows */}
        <div className="divide-y divide-gray-100">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="bg-white px-4 py-4">
              <div className="flex gap-3">
                <div className="mt-6 h-5 w-5 shrink-0 animate-pulse rounded bg-gray-100" />
                <div className="h-20 w-20 shrink-0 animate-pulse rounded-xl bg-gray-100" />
                <div className="min-w-0 flex-1 space-y-2">
                  <div className="h-4 w-full animate-pulse rounded bg-gray-100" />
                  <div className="h-4 w-3/4 animate-pulse rounded bg-gray-100" />
                  <div className="mt-2 flex items-end justify-between">
                    <div className="space-y-1.5">
                      <div className="h-5 w-24 animate-pulse rounded bg-gray-100" />
                      <div className="h-3 w-20 animate-pulse rounded bg-gray-100" />
                    </div>
                    <div className="h-9 w-28 animate-pulse rounded-full bg-gray-100" />
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Desktop summary card */}
      <section className="mt-4 hidden rounded-2xl bg-white p-5 ring-1 ring-gray-100 md:block">
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <div className="h-4 w-32 animate-pulse rounded bg-gray-100" />
            <div className="h-4 w-24 animate-pulse rounded bg-gray-100" />
          </div>
          <div className="flex items-center justify-between border-t border-gray-100 pt-2.5">
            <div className="h-4 w-40 animate-pulse rounded bg-gray-100" />
            <div className="h-6 w-28 animate-pulse rounded bg-gray-100" />
          </div>
        </div>
        <div className="mt-5 h-12 animate-pulse rounded-full bg-gray-100" />
        <div className="mt-3 h-10 animate-pulse rounded-full bg-gray-100" />
      </section>

      {/* Mobile sticky bar */}
      <div className="fixed inset-x-0 z-40 border-t border-gray-100 bg-white px-4 py-3 md:hidden [bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom))]">
        <div className="mx-auto flex max-w-3xl items-center gap-3">
          <div className="h-6 w-16 shrink-0 animate-pulse rounded bg-gray-100" />
          <div className="flex-1 space-y-1 text-right">
            <div className="ml-auto h-3 w-12 animate-pulse rounded bg-gray-100" />
            <div className="ml-auto h-5 w-24 animate-pulse rounded bg-gray-100" />
          </div>
          <div className="h-12 w-32 shrink-0 animate-pulse rounded-full bg-gray-100" />
        </div>
      </div>
    </div>
  );
}
