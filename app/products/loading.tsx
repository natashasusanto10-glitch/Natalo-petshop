export default function ProductsLoading() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-4 md:py-10">
      <div className="mb-5 md:mb-6">
        <div className="h-7 w-44 animate-pulse rounded-xl bg-gray-100" />
        <div className="mt-2 h-3.5 w-56 animate-pulse rounded-lg bg-gray-100" />
      </div>
      <div className="mb-5 flex gap-2 overflow-hidden md:mb-6">
        {[...Array(5)].map((_, i) => (
          <div key={i} className="h-9 w-24 shrink-0 animate-pulse rounded-full bg-gray-100" />
        ))}
      </div>
      <div className="mb-3 h-3 w-40 animate-pulse rounded bg-gray-100" />
      <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-3 xl:grid-cols-4">
        {[...Array(8)].map((_, i) => (
          <div key={i} className="overflow-hidden rounded-2xl border border-gray-100 bg-white">
            <div className="aspect-square animate-pulse bg-gray-100" />
            <div className="space-y-2 p-3 md:p-4">
              <div className="h-4 w-3/4 animate-pulse rounded-lg bg-gray-100" />
              <div className="h-3 w-1/2 animate-pulse rounded-lg bg-gray-100" />
              <div className="mt-3 h-5 w-1/3 animate-pulse rounded-lg bg-gray-100" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
