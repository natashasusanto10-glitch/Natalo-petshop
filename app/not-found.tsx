import Link from "next/link";

export default function NotFound() {
  return (
    <div className="flex min-h-[70vh] items-center justify-center bg-[#f9f9f7] px-6 py-16">
      <div className="w-full max-w-[420px] text-center">
        <div className="mb-3 text-5xl" aria-hidden="true">
          🐾
        </div>
        <h1 className="mb-2 text-7xl font-medium leading-none text-[#D85A30]">
          404
        </h1>
        <h2 className="mb-3 text-xl font-medium text-zinc-950">
          Halaman tidak ditemukan
        </h2>
        <p className="mb-6 text-sm leading-6 text-zinc-500">
          Sepertinya halaman yang kamu cari sudah dipindah, dihapus, atau tidak
          pernah ada. Mungkin produknya sudah habis?
        </p>
        <div className="mb-8 flex flex-wrap justify-center gap-3">
          <Link
            href="/"
            className="rounded-lg bg-[#D85A30] px-6 py-3 text-sm font-medium text-white transition hover:bg-[#c64d27]"
          >
            Kembali ke Beranda
          </Link>
          <Link
            href="/products"
            className="rounded-lg border border-zinc-200 bg-white px-6 py-3 text-sm text-zinc-700 transition hover:border-zinc-300 hover:bg-zinc-50"
          >
            Lihat Semua Produk
          </Link>
        </div>
        <div className="flex justify-center gap-4" aria-hidden="true">
          {["🐱", "🐶", "🐟", "🐰"].map((icon, index) => (
            <span
              className="animate-bounce text-3xl"
              key={icon}
              style={{ animationDuration: `${1 + index * 0.2}s` }}
            >
              {icon}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}
