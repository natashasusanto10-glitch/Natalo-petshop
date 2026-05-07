import Link from "next/link";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/prisma";

function toSlug(name: string) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-");
}

export default function AdminCategoryNewPage() {
  async function createCategory(formData: FormData) {
    "use server";
    const name = String(formData.get("name") || "").trim();
    if (!name) return;

    let slug = toSlug(name);
    const existing = await prisma.category.findUnique({ where: { slug } });
    if (existing) slug = `${slug}-${Date.now()}`;

    await prisma.category.create({ data: { name, slug } });
    redirect("/admin/categories");
  }

  return (
    <div className="mx-auto max-w-lg px-4 py-10">
      <Link href="/admin/categories" className="text-sm font-bold text-zinc-500 hover:text-zinc-950">
        ← Kembali ke kategori
      </Link>
      <h1 className="mt-2 text-3xl font-black tracking-tight text-zinc-950">Tambah Kategori</h1>

      <form action={createCategory} className="mt-8 space-y-5">
        <div>
          <label className="block text-sm font-medium text-zinc-700">
            Nama kategori <span className="text-red-500">*</span>
          </label>
          <input
            name="name"
            required
            placeholder="Contoh: Pakan Ikan"
            className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-zinc-600"
          />
          <p className="mt-1 text-xs text-zinc-400">Slug akan dibuat otomatis dari nama.</p>
        </div>

        <div className="flex gap-3 pt-2">
          <button
            type="submit"
            className="rounded-full bg-zinc-950 px-6 py-3 text-sm font-bold text-white"
          >
            Simpan
          </button>
          <Link
            href="/admin/categories"
            className="rounded-full border border-zinc-300 px-6 py-3 text-sm font-bold"
          >
            Batal
          </Link>
        </div>
      </form>
    </div>
  );
}
