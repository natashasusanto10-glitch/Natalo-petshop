export default function ProductsLoading() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      <div className="mb-8">
        <div className="h-8 w-48 animate-pulse rounded-xl bg-gray-200" />
        <div className="mt-2 h-4 w-64 animate-pulse rounded-lg bg-gray-100" />
      </div>
      <div className="mb-8 flex gap-2">
        {[...Array(4)].map((_, i) => (
          <div key={i} className="h-9 w-24 animate-pulse rounded-full bg-gray-200" />
        ))}
      </div>
      <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {[...Array(8)].map((_, i) => (
          <div key={i} className="overflow-hidden rounded-2xl bg-gray-100">
            <div className="aspect-square animate-pulse bg-gray-200" />
            <div className="p-4 space-y-2">
              <div className="h-4 w-3/4 animate-pulse rounded-lg bg-gray-200" />
              <div className="h-3 w-1/2 animate-pulse rounded-lg bg-gray-100" />
              <div className="h-5 w-1/3 animate-pulse rounded-lg bg-gray-200 mt-3" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
