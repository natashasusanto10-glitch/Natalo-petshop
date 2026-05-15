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
    <div className="mx-auto max-w-3xl px-4 py-5 md:py-10">
      <div className="flex items-end justify-between gap-3 md:gap-4">
        <div className="min-w-0">
          <Link href="/admin" className="hidden text-sm font-bold text-zinc-500 hover:text-zinc-950 md:inline">
            ← Dashboard
          </Link>
          <h1 className="text-2xl font-black tracking-tight text-zinc-950 md:mt-2 md:text-3xl">Kategori</h1>
        </div>
        <Link
          href="/admin/categories/new"
          className="shrink-0 rounded-full bg-zinc-950 px-4 py-2 text-xs font-bold text-white md:px-5 md:py-3 md:text-sm"
        >
          + Tambah
        </Link>
      </div>

      <div className="mt-5 space-y-3 md:mt-8">
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
            className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-zinc-200 p-4"
          >
            <div className="min-w-0 flex-1">
              <p className="truncate font-semibold text-zinc-950">{cat.name}</p>
              <p className="mt-0.5 truncate text-sm text-zinc-400">
                /{cat.slug} • {cat._count.products} produk
              </p>
            </div>

            <div className="flex shrink-0 items-center gap-2">
              <Link
                href={`/admin/categories/${cat.id}/edit`}
                className="rounded-full border border-zinc-300 px-3 py-1.5 text-xs font-bold hover:bg-zinc-50 md:px-4 md:py-2 md:text-sm"
              >
                Edit
              </Link>

              <form action={deleteCategory}>
                <input type="hidden" name="id" value={cat.id} />
                <button
                  type="submit"
                  disabled={cat._count.products > 0}
                  className="rounded-full border border-zinc-300 px-3 py-1.5 text-xs font-bold text-red-500 hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-40 md:px-4 md:py-2 md:text-sm"
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
