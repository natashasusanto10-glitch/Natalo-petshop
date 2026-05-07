import Link from "next/link";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";

export default async function AdminCategoriesPage() {
  const categories = await prisma.category.findMany({
    orderBy: { name: "asc" },
    include: { _count: { select: { products: true } } },
  });

  async function deleteCategory(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    const count = await prisma.product.count({ where: { categoryId: id } });
    if (count > 0) return; // jangan hapus kalau masih ada produk
    await prisma.category.delete({ where: { id } });
    revalidatePath("/admin/categories");
    redirect("/admin/categories");
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-10">
      <div className="flex items-center justify-between gap-4">
        <div>
          <Link href="/admin" className="text-sm font-bold text-zinc-500 hover:text-zinc-950">
            ← Dashboard
          </Link>
          <h1 className="mt-2 text-3xl font-black tracking-tight text-zinc-950">Kategori</h1>
        </div>
        <Link
          href="/admin/categories/new"
          className="rounded-full bg-zinc-950 px-5 py-3 text-sm font-bold text-white"
        >
          + Tambah kategori
        </Link>
      </div>

      <div className="mt-8 space-y-3">
        {categories.length === 0 && (
          <p className="rounded-2xl bg-zinc-50 p-5 text-sm text-zinc-600">
            Belum ada kategori.{" "}
            <Link href="/admin/categories/new" className="font-semibold underline">
              Tambah sekarang
            </Link>
          </p>
        )}

        {categories.map((cat) => (
          <div
            key={cat.id}
            className="flex items-center justify-between gap-4 rounded-2xl border border-zinc-200 p-4"
          >
            <div>
              <p className="font-semibold text-zinc-950">{cat.name}</p>
              <p className="mt-0.5 text-sm text-zinc-400">
                /{cat.slug} • {cat._count.products} produk
              </p>
            </div>

            <div className="flex items-center gap-2">
              <Link
                href={`/admin/categories/${cat.id}/edit`}
                className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-bold hover:bg-zinc-50"
              >
                Edit
              </Link>

              <form action={deleteCategory}>
                <input type="hidden" name="id" value={cat.id} />
                <button
                  type="submit"
                  disabled={cat._count.products > 0}
                  className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-bold text-red-500 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-40"
                  title={cat._count.products > 0 ? "Hapus produk di kategori ini dulu" : "Hapus kategori"}
                >
                  Hapus
                </button>
              </form>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
