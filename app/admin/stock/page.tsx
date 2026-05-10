import { prisma } from "@/lib/prisma";
import Link from "next/link";

export default async function AdminStockPage() {
  // Hanya produk aktif. Produk soft-archive (isActive=false, biasanya hasil
  // reset yg melindungi history pesanan) tidak ditampilkan di sini supaya
  // halaman ini mencerminkan stok yg masih dijual saja.
  const products = await prisma.product.findMany({
    where: { isActive: true },
    orderBy: { stock: "asc" },
    select: {
      id: true,
      name: true,
      stock: true,
      isActive: true,
      category: { select: { name: true } },
    },
  });

  const lowStock = products.filter((p) => p.stock <= 5);
  const outOfStock = products.filter((p) => p.stock === 0);

  return (
    <div className="mx-auto max-w-4xl px-4 py-6 lg:py-10">
      <div>
        <h1 className="text-2xl font-black tracking-tight text-zinc-950 lg:text-3xl">Stok</h1>
        <p className="mt-1 text-sm text-zinc-500">Monitor stok produk dan perbarui jika diperlukan.</p>
      </div>

      {/* Summary */}
      <div className="mt-6 grid grid-cols-3 gap-3">
        <div className="rounded-2xl border border-zinc-100 bg-white p-4">
          <p className="text-xs font-semibold text-zinc-500">Total Produk</p>
          <p className="mt-1 text-2xl font-black text-zinc-900">{products.length}</p>
        </div>
        <div className="rounded-2xl border border-amber-100 bg-amber-50 p-4">
          <p className="text-xs font-semibold text-amber-600">Stok Menipis</p>
          <p className="mt-1 text-2xl font-black text-amber-700">{lowStock.length}</p>
        </div>
        <div className="rounded-2xl border border-red-100 bg-red-50 p-4">
          <p className="text-xs font-semibold text-red-600">Habis</p>
          <p className="mt-1 text-2xl font-black text-red-700">{outOfStock.length}</p>
        </div>
      </div>

      {/* Product stock list */}
      <div className="mt-6 overflow-hidden rounded-3xl border border-zinc-200 bg-white">
        {products.length === 0 ? (
          <div className="p-12 text-center text-sm text-zinc-500">Belum ada produk.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-zinc-100 bg-zinc-50">
                  <th className="px-5 py-4 text-left font-semibold text-zinc-600">Produk</th>
                  <th className="px-5 py-4 text-left font-semibold text-zinc-600 hidden sm:table-cell">Kategori</th>
                  <th className="px-5 py-4 text-right font-semibold text-zinc-600">Stok</th>
                  <th className="px-5 py-4 text-left font-semibold text-zinc-600">Status</th>
                  <th className="px-5 py-4" />
                </tr>
              </thead>
              <tbody>
                {products.map((product) => (
                  <tr
                    key={product.id}
                    className="border-b border-zinc-100 last:border-0 hover:bg-zinc-50 transition"
                  >
                    <td className="px-5 py-4">
                      <p className="font-semibold text-zinc-900">{product.name}</p>
                    </td>
                    <td className="px-5 py-4 text-zinc-500 hidden sm:table-cell">
                      {product.category?.name ?? "-"}
                    </td>
                    <td className="px-5 py-4 text-right">
                      <span
                        className={`font-bold ${
                          product.stock === 0
                            ? "text-red-600"
                            : product.stock <= 5
                            ? "text-amber-600"
                            : "text-zinc-900"
                        }`}
                      >
                        {product.stock}
                      </span>
                    </td>
                    <td className="px-5 py-4">
                      {product.stock === 0 ? (
                        <span className="rounded-full bg-red-100 px-2.5 py-1 text-xs font-bold text-red-700">Habis</span>
                      ) : product.stock <= 5 ? (
                        <span className="rounded-full bg-amber-100 px-2.5 py-1 text-xs font-bold text-amber-700">Menipis</span>
                      ) : (
                        <span className="rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-bold text-emerald-700">Tersedia</span>
                      )}
                    </td>
                    <td className="px-5 py-4 text-right">
                      <Link
                        href={`/admin/products/${product.id}/edit`}
                        className="rounded-full border border-zinc-200 px-3 py-1.5 text-xs font-bold hover:border-zinc-400 transition"
                      >
                        Edit
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
