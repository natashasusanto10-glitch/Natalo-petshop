import { prisma } from "@/lib/prisma";
import { notFound, redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import Link from "next/link";
import { getSession } from "@/lib/auth";

async function requireAdmin() {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") redirect("/admin/login");
}

export default async function EditBrandPage({ params }: { params: Promise<{ id: string }> }) {
  await requireAdmin();

  const { id } = await params;
  const brand = await prisma.brand.findUnique({ where: { id } }).catch(() => null);
  if (!brand) return notFound();

  async function updateBrand(formData: FormData) {
    "use server";
    await requireAdmin();

    const name = (formData.get("name") as string)?.trim();
    const slug = (formData.get("slug") as string)?.trim() || name.toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9-]/g, "");
    if (!name) return;
    await prisma.brand.update({ where: { id }, data: { name, slug } });
    revalidatePath("/admin/brands");
    redirect("/admin/brands");
  }

  return (
    <div className="mx-auto max-w-lg px-4 py-6 lg:py-10">
      <Link href="/admin/brands" className="text-sm font-semibold text-orange-500 hover:underline">
        ← Kembali ke Brand
      </Link>

      <h1 className="mt-4 text-2xl font-black tracking-tight text-zinc-950">Edit Brand</h1>

      <form action={updateBrand} className="mt-8 space-y-5">
        <div>
          <label className="block text-sm font-semibold text-zinc-700">Nama Brand</label>
          <input
            name="name"
            defaultValue={brand.name}
            required
            className="mt-1.5 w-full rounded-2xl border border-zinc-200 px-4 py-3 text-sm outline-none focus:border-orange-400 focus:ring-2 focus:ring-orange-100"
          />
        </div>
        <div>
          <label className="block text-sm font-semibold text-zinc-700">Slug</label>
          <input
            name="slug"
            defaultValue={brand.slug}
            className="mt-1.5 w-full rounded-2xl border border-zinc-200 px-4 py-3 text-sm text-zinc-500 outline-none focus:border-orange-400 focus:ring-2 focus:ring-orange-100"
            placeholder="auto-generated dari nama"
          />
        </div>
        <button
          type="submit"
          className="w-full rounded-full bg-orange-500 py-3 text-sm font-bold text-white transition hover:bg-orange-600"
        >
          Simpan Perubahan
        </button>
      </form>
    </div>
  );
}
