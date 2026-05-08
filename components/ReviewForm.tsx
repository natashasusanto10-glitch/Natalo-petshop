import Link from "next/link";

/**
 * Info card pengganti form ulasan publik.
 * Review hanya bisa dikirim oleh customer yang ordernya sudah DELIVERED,
 * via halaman "Pesanan Saya". Lihat /api/reviews POST.
 */
export function ReviewForm({ productId: _productId }: { productId: string }) {
  return (
    <div className="rounded-2xl border border-blue-100 bg-blue-50 p-4 text-sm text-zinc-700">
      <p className="font-semibold text-zinc-900">Sudah pernah beli produk ini?</p>
      <p className="mt-1 text-zinc-600">
        Kamu bisa menulis ulasan dari halaman pesananmu setelah barang diterima.
      </p>
      <Link
        href="/member/orders"
        className="mt-3 inline-flex items-center justify-center rounded-full bg-blue-500 px-4 py-2 text-xs font-bold text-white transition hover:bg-blue-600"
      >
        Buka Pesanan Saya →
      </Link>
    </div>
  );
}
