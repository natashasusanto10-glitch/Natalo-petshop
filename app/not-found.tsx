import Link from "next/link";

export default function NotFound() {
  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
      <span className="text-6xl">🐾</span>
      <h1 className="mt-4 text-2xl font-black text-gray-900">Halaman Tidak Ditemukan</h1>
      <p className="mt-2 max-w-sm text-sm text-gray-500">
        Halaman yang kamu cari tidak ada atau sudah dipindahkan.
      </p>
      <div className="mt-6 flex flex-wrap justify-center gap-3">
        <Link
          href="/"
          className="rounded-full bg-orange-500 px-6 py-3 text-sm font-bold text-white transition hover:bg-orange-600"
        >
          Kembali ke Beranda
        </Link>
        <Link
          href="/products"
          className="rounded-full border border-gray-200 px-6 py-3 text-sm font-bold text-gray-700 transition hover:border-orange-300 hover:text-orange-500"
        >
          Lihat Produk
        </Link>
      </div>
    </div>
  );
}
