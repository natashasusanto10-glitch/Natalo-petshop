import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
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
                <Button
                  href={`/admin/categories/${cat.id}/edit`}
                  variant="secondary"
                  size="md"
                >
                  ✏️ Edit
                </Button>

                <form action={deleteCategory}>
                  <input type="hidden" name="id" value={cat.id} />
                  <Button
                    type="submit"
                    variant="dangerSoft"
                    size="md"
                    disabled={cat._count.products > 0}
                    title={
                      cat._count.products > 0
                        ? "Hapus produk di kategori ini dulu"
                        : "Hapus kategori"
                    }
                  >
                    🗑️ Hapus
                  </Button>
                </form>
              </div>
            </div>
          ))}
        </div>
      )}
    </AdminPage>
  );
}
