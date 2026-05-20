/**
 * /admin/diskon/promo-toko/new — Stub placeholder.
 *
 * Real form (create ProductDiscount: nama, periode, % atau nominal,
 * pilih produk multi-checklist, max cap, dst.) akan dibuat di Phase 1B.
 * Untuk sekarang tampilkan info "coming soon" supaya CTA dari hub
 * tidak ke 404.
 */
import Link from "next/link";

export default function PromoTokoNewPlaceholder() {
  return (
    <div className="mx-auto max-w-2xl px-4 py-10">
      <Link
        href="/admin/diskon"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke Buat Diskon
      </Link>
      <div className="mt-6 rounded-2xl border border-amber-200 bg-amber-50 p-8 text-center">
        <p className="text-3xl">🚧</p>
        <h1 className="mt-3 text-xl font-black text-amber-900">
          Form Promo Toko sedang dikerjakan
        </h1>
        <p className="mt-2 text-sm text-amber-800">
          Untuk sementara, atur harga coret per-produk langsung dari
          halaman edit produk masing-masing.
        </p>
        <Link
          href="/admin/products"
          className="mt-5 inline-block rounded-full bg-amber-600 px-5 py-2 text-sm font-bold text-white hover:bg-amber-700"
        >
          Buka Daftar Produk
        </Link>
      </div>
    </div>
  );
}
