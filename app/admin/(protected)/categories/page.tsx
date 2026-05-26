import Link from "next/link";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { PageHeader, EmptyState, Badge } from "@/components/admin/ui";

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
      <PageHeader
        title="Kategori"
        subtitle={`${categories.length} kategori terdaftar.`}
        actions={
          <>
            <Link
              href="/admin/dashboard"
              className="inline-flex items-center gap-1.5 rounded-full border border-zinc-200 bg-white px-3.5 py-2 text-xs font-bold text-zinc-700 transition hover:border-zinc-400 hover:bg-zinc-50"
            >
              ← Dashboard
            </Link>
            <Link
              href="/admin/categories/new"
              className="inline-flex items-center gap-1.5 rounded-full bg-natalo-600 px-4 py-2 text-xs font-bold text-white shadow-sm transition hover:bg-natalo-700 md:text-sm"
            >
              + Tambah Kategori
            </Link>
          </>
        }
      />

      {categories.length === 0 ? (
        <div className="mt-6 rounded-2xl border border-zinc-200 bg-white">
          <EmptyState
            icon="🏷️"
            title="Belum ada kategori"
            description="Tambahkan kategori pertama untuk mengelompokkan produk."
            action={{
              label: "Tambah kategori pertama",
              href: "/admin/categories/new",
            }}
            size="full"
          />
        </div>
      ) : (
        <div className="mt-6 space-y-3">
          {categories.map((cat) => (
            <div
              key={cat.id}
              className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-zinc-200 bg-white p-4 transition hover:border-zinc-300 hover:shadow-sm md:p-5"
            >
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="truncate font-black text-zinc-950">{cat.name}</p>
                  <Badge variant={cat._count.products > 0 ? "info" : "neutral"}>
                    {cat._count.products} produk
                  </Badge>
                </div>
                <p className="mt-1 truncate text-xs text-zinc-500">
                  /{cat.slug}
                </p>
              </div>

              <div className="flex shrink-0 items-center gap-2">
                <Link
                  href={`/admin/categories/${cat.id}/edit`}
                  className="rounded-full border border-zinc-200 bg-white px-3 py-1.5 text-xs font-bold text-zinc-700 transition hover:border-zinc-400 hover:bg-zinc-50 md:px-4 md:py-2 md:text-sm"
                >
                  ✏️ Edit
                </Link>

                <form action={deleteCategory}>
                  <input type="hidden" name="id" value={cat.id} />
                  <button
                    type="submit"
                    disabled={cat._count.products > 0}
                    className="rounded-full border border-red-200 bg-white px-3 py-1.5 text-xs font-bold text-red-600 transition hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-40 md:px-4 md:py-2 md:text-sm"
                    title={
                      cat._count.products > 0
                        ? "Hapus produk di kategori ini dulu"
                        : "Hapus kategori"
                    }
                  >
                    🗑️ Hapus
                  </button>
                </form>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
