import { revalidatePath } from "next/cache";
import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { ConfirmSubmitButton } from "@/components/ConfirmSubmitButton";
import {
  PageHeader,
  StatCard,
  EmptyState,
  Badge,
  AdminPage,
  Button,
} from "@/components/admin/ui";

// Halaman ini selalu render fresh — tidak boleh kena Next.js full-route cache
// karena perubahan stok sering & user expect angka-nya selalu akurat.
export const dynamic = "force-dynamic";

export default async function AdminStockPage() {
  // Hanya produk aktif. Produk soft-archive tidak ditampilkan di sini.
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

  async function archiveProduct(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    await prisma.product.update({
      where: { id },
      data: { isActive: false },
    });
    const { syncProduct } = await import("@/lib/search");
    await syncProduct(id).catch(() => {});
    revalidatePath("/admin/stock");
    revalidatePath("/admin/products");
    revalidatePath("/admin/dashboard");
  }

  async function deleteProduct(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));

    // Refuse hapus permanen kalau pernah dipesan — paksa user pakai Arsip.
    const orderCount = await prisma.orderItem.count({ where: { productId: id } });
    if (orderCount > 0) {
      throw new Error(
        `Produk pernah dipesan (${orderCount}× di order). Tidak bisa dihapus permanen — gunakan tombol Arsip.`,
      );
    }

    await prisma.product.delete({ where: { id } });

    const { deleteProductFromIndex } = await import("@/lib/search");
    await deleteProductFromIndex(id).catch(() => {});

    revalidatePath("/admin/stock");
    revalidatePath("/admin/products");
    revalidatePath("/admin/dashboard");
  }

  return (
    <AdminPage maxWidth="lg">
      <PageHeader
        title="📦 Stok"
        subtitle="Monitor stok produk dan perbarui jika diperlukan."
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            ← Dashboard
          </Button>
        }
      />

      <section className="mt-6 grid grid-cols-3 gap-3">
        <StatCard
          label="Total Produk"
          value={products.length}
          helper="Aktif di toko"
          variant="default"
        />
        <StatCard
          label="Stok Menipis"
          value={lowStock.length}
          helper="Stok 1-5"
          variant="warning"
        />
        <StatCard
          label="Habis"
          value={outOfStock.length}
          helper="Stok 0"
          variant="danger"
        />
      </section>

      {products.length === 0 ? (
        <div className="mt-6 rounded-2xl border border-zinc-200 bg-white">
          <EmptyState
            icon="📭"
            title="Belum ada produk"
            description="Tambahkan produk pertama untuk mulai monitor stok."
            action={{
              label: "Tambah produk",
              href: "/admin/products/new",
            }}
            size="full"
          />
        </div>
      ) : (
        <>
          {/* Mobile card list */}
          <div className="mt-5 space-y-3 md:hidden">
            {products.map((product) => (
              <div
                key={product.id}
                className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <p className="line-clamp-2 font-semibold text-zinc-950">{product.name}</p>
                    <p className="mt-0.5 truncate text-xs text-zinc-500">{product.category?.name ?? "Tanpa kategori"}</p>
                  </div>
                  <div className="shrink-0 text-right">
                    <p
                      className={`text-2xl font-black ${
                        product.stock === 0
                          ? "text-red-600"
                          : product.stock <= 5
                          ? "text-amber-600"
                          : "text-zinc-900"
                      }`}
                    >
                      {product.stock}
                    </p>
                    <div className="mt-1">
                      <Badge
                        variant={
                          product.stock === 0
                            ? "danger"
                            : product.stock <= 5
                              ? "warning"
                              : "success"
                        }
                      >
                        {product.stock === 0
                          ? "Habis"
                          : product.stock <= 5
                            ? "Menipis"
                            : "Tersedia"}
                      </Badge>
                    </div>
                  </div>
                </div>
                <div className="mt-3 grid grid-cols-3 gap-2 border-t border-zinc-100 pt-3">
                  <Link
                    href={`/admin/products/${product.id}/edit`}
                    className="rounded-full border border-zinc-200 px-3 py-2 text-center text-xs font-bold hover:border-zinc-400"
                  >
                    Edit
                  </Link>
                  <form action={archiveProduct}>
                    <input type="hidden" name="id" value={product.id} />
                    <ConfirmSubmitButton
                      className="w-full rounded-full border border-amber-200 px-3 py-2 text-xs font-bold text-amber-700 hover:bg-amber-50"
                      message={`Arsipkan "${product.name}"? Produk akan di-set non-aktif dan tidak muncul di toko, tapi history pesanan tetap aman.`}
                    >
                      Arsip
                    </ConfirmSubmitButton>
                  </form>
                  <form action={deleteProduct}>
                    <input type="hidden" name="id" value={product.id} />
                    <ConfirmSubmitButton
                      className="w-full rounded-full border border-red-200 px-3 py-2 text-xs font-bold text-red-600 hover:bg-red-50"
                      message={`Hapus permanen "${product.name}"? Tidak bisa di-undo. Produk yg pernah dipesan tidak bisa dihapus permanen — gunakan Arsip.`}
                    >
                      Hapus
                    </ConfirmSubmitButton>
                  </form>
                </div>
              </div>
            ))}
          </div>

          {/* Desktop table */}
          <div className="mt-6 hidden overflow-hidden rounded-2xl border border-zinc-200 bg-white md:block">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-zinc-100 bg-zinc-50/50">
                    <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Produk
                    </th>
                    <th className="hidden px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500 lg:table-cell">
                      Kategori
                    </th>
                    <th className="px-5 py-3.5 text-right text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Stok
                    </th>
                    <th className="px-5 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Status
                    </th>
                    <th className="px-5 py-3.5 text-right text-[11px] font-black uppercase tracking-wider text-zinc-500">
                      Aksi
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {products.map((product) => (
                    <tr
                      key={product.id}
                      className="border-b border-zinc-100 transition last:border-0 hover:bg-natalo-50/40"
                    >
                      <td className="px-5 py-4">
                        <p className="font-semibold text-zinc-900">{product.name}</p>
                      </td>
                      <td className="px-5 py-4 text-zinc-500 hidden lg:table-cell">
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
                        <Badge
                          variant={
                            product.stock === 0
                              ? "danger"
                              : product.stock <= 5
                                ? "warning"
                                : "success"
                          }
                          size="md"
                        >
                          {product.stock === 0
                            ? "Habis"
                            : product.stock <= 5
                              ? "Menipis"
                              : "Tersedia"}
                        </Badge>
                      </td>
                      <td className="px-5 py-4">
                        <div className="flex items-center justify-end gap-1.5">
                          <Link
                            href={`/admin/products/${product.id}/edit`}
                            className="rounded-full border border-zinc-200 px-3 py-1.5 text-xs font-bold hover:border-zinc-400 transition"
                          >
                            Edit
                          </Link>
                          <form action={archiveProduct}>
                            <input type="hidden" name="id" value={product.id} />
                            <ConfirmSubmitButton
                              className="rounded-full border border-amber-200 px-3 py-1.5 text-xs font-bold text-amber-700 hover:bg-amber-50 transition"
                              message={`Arsipkan "${product.name}"? Produk akan di-set non-aktif dan tidak muncul di toko, tapi history pesanan tetap aman.`}
                            >
                              Arsip
                            </ConfirmSubmitButton>
                          </form>
                          <form action={deleteProduct}>
                            <input type="hidden" name="id" value={product.id} />
                            <ConfirmSubmitButton
                              className="rounded-full border border-red-200 px-3 py-1.5 text-xs font-bold text-red-600 hover:bg-red-50 transition"
                              message={`Hapus permanen "${product.name}"? Tidak bisa di-undo. Produk yg pernah dipesan tidak bisa dihapus permanen — gunakan Arsip.`}
                            >
                              Hapus
                            </ConfirmSubmitButton>
                          </form>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </AdminPage>
  );
}
