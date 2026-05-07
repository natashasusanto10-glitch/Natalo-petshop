export default function OfflinePage() {
  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
      <span className="text-7xl">🐾</span>
      <h1 className="mt-6 text-2xl font-black text-gray-900">Kamu sedang offline</h1>
      <p className="mt-3 max-w-sm text-gray-500">
        Koneksi internet tidak tersedia. Halaman ini mungkin sudah tersimpan di cache dan bisa diakses saat online kembali.
      </p>
      <a
        href="/"
        className="mt-8 rounded-full bg-natalo-600 px-7 py-3 text-sm font-bold text-white transition hover:bg-natalo-700"
      >
        Coba lagi
      </a>
    </div>
  );
}
