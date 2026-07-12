import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { FiEdit2, FiTrash2 } from "react-icons/fi";
import { prisma } from "@/lib/prisma";
import { PageHeader, EmptyState, Badge, AdminPage, Button } from "@/components/admin/ui";

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
    <AdminPage maxWidth="lg">
      <PageHeader
        title="Kategori"
        subtitle={`${categories.length} kategori terdaftar.`}
        actions={
          <>
            <Button href="/admin/dashboard" variant="secondary" size="sm">
              ← Dashboard
            </Button>
            <Button href="/admin/categories/new" size="sm">
              + Tambah Kategori
            </Button>
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
        <div className="mt-6 overflow-hidden rounded-2xl border border-zinc-200 bg-white">
          <div className="divide-y divide-zinc-100">
            {categories.map((cat) => (
              <div
                key={cat.id}
                className="flex items-center gap-3 px-4 py-3 transition hover:bg-zinc-50/60"
              >
                <div className="min-w-0 flex-1">
                  <span className="truncate text-sm font-bold text-zinc-900">
                    {cat.name}
                  </span>
                  <span className="ml-2 truncate text-xs text-zinc-400">
                    /{cat.slug}
                  </span>
                </div>

                <Badge variant={cat._count.products > 0 ? "info" : "neutral"}>
                  {cat._count.products} produk
                </Badge>

                <div className="flex shrink-0 items-center gap-1.5">
                  <Button
                    href={`/admin/categories/${cat.id}/edit`}
                    variant="secondary"
                    size="sm"
                    aria-label={`Edit ${cat.name}`}
                    title="Edit"
                  >
                    <FiEdit2 className="h-3.5 w-3.5" />
                  </Button>

                  <form action={deleteCategory}>
                    <input type="hidden" name="id" value={cat.id} />
                    <Button
                      type="submit"
                      variant="dangerSoft"
                      size="sm"
                      disabled={cat._count.products > 0}
                      aria-label={
                        cat._count.products > 0
                          ? `Hapus ${cat.name} (nonaktif — masih ada produk)`
                          : `Hapus ${cat.name}`
                      }
                      title={
                        cat._count.products > 0
                          ? "Hapus produk di kategori ini dulu"
                          : "Hapus kategori"
                      }
                    >
                      <FiTrash2 className="h-3.5 w-3.5" />
                    </Button>
                  </form>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </AdminPage>
  );
}
