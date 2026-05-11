export default function CheckoutLoading() {
  return (
    <div className="mx-auto max-w-6xl gap-8 px-3 py-3 pb-32 lg:grid lg:grid-cols-[1fr_360px] lg:px-4 lg:py-10 lg:pb-10">
      <div>
        <div className="hidden h-9 w-40 animate-pulse rounded-lg bg-gray-100 lg:block" />

        <div className="space-y-3 lg:mt-8 lg:space-y-4">
          {/* Address card */}
          <section className="overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm">
            <div className="flex items-start gap-3 p-3">
              <div className="h-9 w-9 shrink-0 animate-pulse rounded-full bg-gray-100" />
              <div className="min-w-0 flex-1 space-y-2">
                <div className="h-3 w-32 animate-pulse rounded bg-gray-100" />
                <div className="h-4 w-2/3 animate-pulse rounded bg-gray-100" />
                <div className="h-3 w-full animate-pulse rounded bg-gray-100" />
              </div>
              <div className="h-4 w-12 shrink-0 animate-pulse rounded bg-gray-100" />
            </div>
          </section>

          {/* Item list */}
          <section className="overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm">
            <div className="border-b border-gray-100 px-4 py-3">
              <div className="h-4 w-32 animate-pulse rounded bg-gray-100" />
            </div>
            <div className="divide-y divide-gray-100">
              {[...Array(2)].map((_, i) => (
                <div key={i} className="flex gap-3 px-4 py-3">
                  <div className="h-16 w-16 shrink-0 animate-pulse rounded-xl bg-gray-100" />
                  <div className="min-w-0 flex-1 space-y-2">
                    <div className="h-4 w-3/4 animate-pulse rounded bg-gray-100" />
                    <div className="h-3 w-1/2 animate-pulse rounded bg-gray-100" />
                    <div className="h-4 w-24 animate-pulse rounded bg-gray-100" />
                  </div>
                </div>
              ))}
            </div>
          </section>

          {/* Shipping method */}
          <section className="overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm">
            <div className="border-b border-gray-100 px-4 py-3">
              <div className="h-4 w-40 animate-pulse rounded bg-gray-100" />
            </div>
            <div className="space-y-2 px-4 py-3">
              <div className="h-14 animate-pulse rounded-xl bg-gray-100" />
              <div className="h-14 animate-pulse rounded-xl bg-gray-100" />
            </div>
          </section>

          {/* Voucher */}
          <section className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
            <div className="h-12 animate-pulse rounded-xl bg-gray-100" />
          </section>

          {/* Payment */}
          <section className="overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm">
            <div className="border-b border-gray-100 px-4 py-3">
              <div className="h-4 w-36 animate-pulse rounded bg-gray-100" />
            </div>
            <div className="space-y-2 px-4 py-3">
              <div className="h-12 animate-pulse rounded-xl bg-gray-100" />
              <div className="h-12 animate-pulse rounded-xl bg-gray-100" />
            </div>
          </section>
        </div>
      </div>

      {/* Desktop summary */}
      <aside className="hidden lg:block">
        <div className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
          <div className="h-5 w-24 animate-pulse rounded bg-gray-100" />
          <div className="mt-4 space-y-2.5">
            {[...Array(3)].map((_, i) => (
              <div key={i} className="flex items-center justify-between">
                <div className="h-3.5 w-24 animate-pulse rounded bg-gray-100" />
                <div className="h-3.5 w-20 animate-pulse rounded bg-gray-100" />
              </div>
            ))}
            <div className="flex items-center justify-between border-t border-gray-100 pt-2.5">
              <div className="h-4 w-16 animate-pulse rounded bg-gray-100" />
              <div className="h-6 w-28 animate-pulse rounded bg-gray-100" />
            </div>
          </div>
          <div className="mt-5 h-12 animate-pulse rounded-full bg-gray-100" />
        </div>
      </aside>

      {/* Mobile sticky bar */}
      <div className="fixed inset-x-0 z-40 border-t border-gray-100 bg-white px-4 py-3 lg:hidden [bottom:env(safe-area-inset-bottom)]">
        <div className="mx-auto flex max-w-6xl items-center gap-3">
          <div className="flex-1 space-y-1">
            <div className="h-3 w-12 animate-pulse rounded bg-gray-100" />
            <div className="h-5 w-28 animate-pulse rounded bg-gray-100" />
          </div>
          <div className="h-12 w-36 shrink-0 animate-pulse rounded-full bg-gray-100" />
        </div>
      </div>
    </div>
  );
}
