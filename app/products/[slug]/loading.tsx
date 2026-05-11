export default function ProductDetailLoading() {
  return (
    <div className="bg-gray-50 md:bg-white">
      <div className="hidden border-b border-gray-100 bg-white md:block">
        <div className="mx-auto max-w-6xl px-4 py-3">
          <div className="h-4 w-64 animate-pulse rounded bg-gray-100" />
        </div>
      </div>

      <div className="mx-auto max-w-6xl pb-40 md:px-4 md:py-10 md:pb-10">
        <div className="grid gap-2 bg-gray-50 md:grid-cols-2 md:gap-10 md:bg-white">
          {/* Carousel */}
          <div className="relative mx-auto aspect-square w-full max-h-[360px] animate-pulse bg-gray-100 md:max-h-none md:rounded-3xl" />

          {/* Right column */}
          <section className="space-y-4 bg-white px-4 py-4 md:rounded-3xl md:border md:border-gray-100 md:p-6">
            {/* PriceBlock */}
            <div className="flex items-center justify-between">
              <div className="space-y-2">
                <div className="h-7 w-32 animate-pulse rounded-lg bg-gray-100" />
                <div className="h-3 w-20 animate-pulse rounded bg-gray-100" />
              </div>
              <div className="h-10 w-10 animate-pulse rounded-full bg-gray-100" />
            </div>

            {/* Title */}
            <div className="space-y-2 pt-1">
              <div className="h-4 w-full animate-pulse rounded bg-gray-100" />
              <div className="h-4 w-4/5 animate-pulse rounded bg-gray-100" />
            </div>

            {/* Social proof row */}
            <div className="flex gap-3 pt-1">
              <div className="h-4 w-20 animate-pulse rounded bg-gray-100" />
              <div className="h-4 w-24 animate-pulse rounded bg-gray-100" />
            </div>

            {/* Voucher card */}
            <div className="h-16 animate-pulse rounded-2xl bg-gray-100" />

            {/* Trust info */}
            <div className="h-14 animate-pulse rounded-2xl bg-gray-100" />

            {/* Action area */}
            <div className="space-y-2 pt-2">
              <div className="h-12 w-full animate-pulse rounded-full bg-gray-100" />
              <div className="hidden h-12 w-full animate-pulse rounded-full bg-gray-100 md:block" />
            </div>
          </section>
        </div>

        {/* Tabs section */}
        <section className="mt-2 bg-white px-4 py-5 md:mt-10 md:rounded-3xl md:border md:border-gray-100 md:p-6">
          <div className="flex gap-3">
            <div className="h-9 w-24 animate-pulse rounded-full bg-gray-100" />
            <div className="h-9 w-24 animate-pulse rounded-full bg-gray-100" />
          </div>
          <div className="mt-4 space-y-2">
            <div className="h-3 w-full animate-pulse rounded bg-gray-100" />
            <div className="h-3 w-11/12 animate-pulse rounded bg-gray-100" />
            <div className="h-3 w-3/4 animate-pulse rounded bg-gray-100" />
          </div>
        </section>
      </div>

      {/* Sticky bottom bar — match StickyAddToCartBar */}
      <div className="fixed inset-x-0 z-40 border-t border-gray-100 bg-white px-3 py-2 md:hidden [bottom:calc(var(--natalo-bottom-nav-height)+env(safe-area-inset-bottom))]">
        <div className="grid grid-cols-[0.9fr_1.15fr_1.35fr] gap-2">
          <div className="h-11 animate-pulse rounded-xl bg-gray-100" />
          <div className="h-11 animate-pulse rounded-xl bg-gray-100" />
          <div className="h-11 animate-pulse rounded-xl bg-gray-100" />
        </div>
      </div>
    </div>
  );
}
