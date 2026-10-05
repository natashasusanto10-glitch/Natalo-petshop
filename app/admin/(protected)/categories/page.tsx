import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { requireAdminSession } from "@/lib/session-guards";
import { CategoriesView } from "@/components/admin/views/CategoriesView";

export default async function AdminCategoriesPage() {
  const categories = await prisma.category.findMany({
    orderBy: { name: "asc" },
    include: { _count: { select: { products: true } } },
  });

  async function deleteCategory(formData: FormData) {
    "use server";
    await requireAdminSession();
    const id = String(formData.get("id"));
    const count = await prisma.product.count({ where: { categoryId: id } });
    if (count > 0) return; // jangan hapus kalau masih ada produk
    await prisma.category.delete({ where: { id } });
    revalidatePath("/admin/categories");
    redirect("/admin/categories");
  }

  return (
    <CategoriesView categories={categories} deleteCategory={deleteCategory} />
  );
}
