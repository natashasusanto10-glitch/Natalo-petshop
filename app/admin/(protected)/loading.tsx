/**
 * Loading skeleton kanonik untuk route group admin (protected).
 * Server component — Next.js otomatis menampilkannya selama segmen di-suspend
 * (mis. saat data fetch awal). Meniru bentuk umum halaman admin: judul + grid
 * kartu, memakai animate-pulse dengan warna netral zinc.
 */
export default function Loading() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      <div className="animate-pulse space-y-8" aria-hidden="true">
        {/* Judul + subjudul */}
        <div className="space-y-3">
          <div className="h-8 w-64 rounded-lg bg-zinc-200" />
          <div className="h-4 w-80 max-w-full rounded-md bg-zinc-200/70" />
        </div>

        {/* Baris ringkasan (mis. StatCard) */}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <div
              key={i}
              className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm"
            >
              <div className="h-3 w-24 rounded bg-zinc-200" />
              <div className="mt-4 h-7 w-20 rounded-md bg-zinc-200" />
            </div>
          ))}
        </div>

        {/* Grid kartu konten */}
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <div
              key={i}
              className="space-y-4 rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm"
            >
              <div className="h-32 w-full rounded-xl bg-zinc-200" />
              <div className="h-4 w-3/4 rounded bg-zinc-200" />
              <div className="h-3 w-1/2 rounded bg-zinc-200/70" />
            </div>
          ))}
        </div>
      </div>

      <span className="sr-only">Memuat…</span>
    </div>
  );
}
