import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";
import { requireAdminSession } from "@/lib/session-guards";
import { revalidatePath } from "next/cache";
import { AdminPage, Button, SubmitButton } from "@/components/admin/ui";

export default async function AdminCategoryEditPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const category = await prisma.category.findUnique({ where: { id } });
  if (!category) return notFound();

  async function updateCategory(formData: FormData) {
    "use server";
    await requireAdminSession();
    const name = String(formData.get("name") || "").trim();
    if (!name) return;

    await prisma.category.update({
      where: { id },
      // Slug is a stable filter/link key; renaming only changes the label.
      data: { name },
    });

    revalidatePath("/admin/categories");
    revalidatePath("/admin/products");
    revalidatePath("/api/categories");
    revalidatePath("/");
    redirect("/admin/categories");
  }

  return (
    <AdminPage maxWidth="md" className="admin-operational-page">
      <Link
        href="/admin/categories"
        className="text-sm font-bold text-zinc-500 hover:text-zinc-950"
      >
        ← Kembali ke kategori
      </Link>
      <h1 className="mt-2 text-2xl font-semibold tracking-tight text-zinc-950 md:text-3xl">
        Edit Kategori
      </h1>
      <p className="mt-1 truncate text-sm text-zinc-600">/{category.slug}</p>

      <form
        action={updateCategory}
        className="admin-operational-form mt-5 space-y-5 md:mt-8"
      >
        <div>
          <label
            htmlFor="category-name"
            className="block text-sm font-medium text-zinc-700"
          >
            Nama kategori <span className="text-red-500">*</span>
          </label>
          <input
            id="category-name"
            name="name"
            required
            defaultValue={category.name}
            className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
          />
          <p className="mt-1 text-xs text-zinc-600">
            Nama ditampilkan di katalog. Kode kategori tetap /{category.slug}.
          </p>
        </div>

        <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row">
          <Button href="/admin/categories" variant="secondary">
            Batal
          </Button>
          <SubmitButton className="flex-1 sm:flex-none">
            Simpan perubahan
          </SubmitButton>
        </div>
      </form>
    </AdminPage>
  );
}
