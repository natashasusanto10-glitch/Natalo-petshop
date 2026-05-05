import Link from "next/link";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { formatRupiah } from "@/lib/format";

export default async function AdminProductsPage() {
  const products = await prisma.product.findMany({
    orderBy: { createdAt: "desc" },
    include: { category: true },
  });

  async function toggleActive(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    const current = formData.get("isActive") === "true";
    await prisma.product.update({ where: { id }, data: { isActive: !current } });
    revalidatePath("/admin/products");
  }

  return (
    <div className="mx-auto max-w-5xl px-4 py-10">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <Link href="/admin" className="text-sm font-bold text-zinc-500 hover:text-zinc-950">
            ← Dashboard
          </Link>
          <h1 className="mt-2 text-3xl font-black tracking-tight text-zinc-950">Produk</h1>
        </div>
        <Link
          href="/admin/products/new"
          className="rounded-full bg-zinc-950 px-5 py-3 text-sm font-bold text-white"
        >
          + Tambah produk
        </Link>
      </div>

      <div className="mt-8 space-y-3">
        {products.length === 0 && (
          <p className="rounded-2xl bg-zinc-50 p-5 text-sm text-zinc-600">
            Belum ada produk.{" "}
            <Link href="/admin/products/new" className="font-semibold underline">
              Tambah sekarang
            </Link>
          </p>
        )}

        {products.map((product) => (
          <div
            key={product.id}
            className={`flex flex-wrap items-center justify-between gap-4 rounded-2xl border p-4 ${
              product.isActive ? "border-zinc-200" : "border-zinc-100 bg-zinc-50 opacity-60"
            }`}
          >
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <p className="truncate font-semibold text-zinc-950">{product.name}</p>
                {!product.isActive && (
                  <span className="shrink-0 rounded-full bg-zinc-200 px-2 py-0.5 text-xs text-zinc-600">
                    Nonaktif
                  </span>
                )}
              </div>
              <p className="mt-1 text-sm text-zinc-500">
                Stok {product.stock} • {product.category?.name ?? "Tanpa kategori"} •{" "}
                {formatRupiah(product.price)}
                {product.memberPrice ? ` (member ${formatRupiah(product.memberPrice)})` : ""}
              </p>
            </div>

            <div className="flex items-center gap-2">
              <Link
                href={`/admin/products/${product.id}/edit`}
                className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-bold hover:bg-zinc-50"
              >
                Edit
              </Link>
              <form action={toggleActive}>
                <input type="hidden" name="id" value={product.id} />
                <input type="hidden" name="isActive" value={String(product.isActive)} />
                <button
                  type="submit"
                  className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-bold hover:bg-zinc-50"
                >
                  {product.isActive ? "Nonaktifkan" : "Aktifkan"}
                </button>
              </form>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
