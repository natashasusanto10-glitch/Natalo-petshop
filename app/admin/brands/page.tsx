import { prisma } from "@/lib/prisma";
import Link from "next/link";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

async function createBrand(formData: FormData) {
  "use server";
  const name = (formData.get("name") as string)?.trim();
  const slug = name.toLowerCase().replace(/\s+/g, "-").replace(/[^a-z0-9-]/g, "");
  if (!name || !slug) return;
  await prisma.brand.create({ data: { name, slug } });
  revalidatePath("/admin/brands");
}

async function deleteBrand(formData: FormData) {
  "use server";
  const id = formData.get("id") as string;
  if (!id) return;
  await prisma.brand.delete({ where: { id } }).catch(() => {});
  revalidatePath("/admin/brands");
  redirect("/admin/brands");
}

export default async function AdminBrandsPage() {
  const brands = await prisma.brand.findMany({ orderBy: { name: "asc" } }).catch(() => []);

  return (
    <div className="mx-auto max-w-4xl px-4 py-6 lg:py-10">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-black tracking-tight text-zinc-950 lg:text-3xl">Brand</h1>
          <p className="mt-1 text-sm text-zinc-500">Kelola brand / merek produk.</p>
        </div>
      </div>

      {/* Add brand form */}
      <form action={createBrand} className="mt-8 flex gap-3">
        <input
          name="name"
          required
          placeholder="Nama brand (contoh: Hikari)"
          className="flex-1 rounded-2xl border border-zinc-200 bg-white px-4 py-3 text-sm outline-none focus:border-orange-400 focus:ring-2 focus:ring-orange-100"
        />
        <button
          type="submit"
          className="rounded-full bg-orange-500 px-6 py-3 text-sm font-bold text-white transition hover:bg-orange-600"
        >
          + Tambah
        </button>
      </form>

      {/* Brand list */}
      <div className="mt-6 rounded-2xl border border-zinc-200 bg-white overflow-hidden">
        {brands.length === 0 ? (
          <div className="py-16 text-center">
            <span className="text-4xl">🏷️</span>
            <p className="mt-3 font-semibold text-zinc-500">Belum ada brand.</p>
            <p className="mt-1 text-sm text-zinc-400">Tambah brand pertama kamu di atas.</p>
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="border-b border-zinc-100 bg-zinc-50">
              <tr>
                <th className="px-5 py-3 text-left font-semibold text-zinc-500">Nama</th>
                <th className="px-5 py-3 text-left font-semibold text-zinc-500">Slug</th>
                <th className="px-5 py-3 text-left font-semibold text-zinc-500">Produk</th>
                <th className="px-5 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-100">
              {brands.map((brand) => (
                <tr key={brand.id} className="hover:bg-zinc-50">
                  <td className="px-5 py-3 font-semibold text-zinc-900">{brand.name}</td>
                  <td className="px-5 py-3 text-zinc-400">{brand.slug}</td>
                  <td className="px-5 py-3 text-zinc-400">—</td>
                  <td className="px-5 py-3 text-right">
                    <div className="flex items-center justify-end gap-2">
                      <Link
                        href={`/admin/brands/${brand.id}/edit`}
                        className="rounded-lg border border-zinc-200 px-3 py-1.5 text-xs font-semibold text-zinc-700 transition hover:border-orange-400 hover:text-orange-600"
                      >
                        Edit
                      </Link>
                      <form action={deleteBrand}>
                        <input type="hidden" name="id" value={brand.id} />
                        <button
                          type="submit"
                          className="rounded-lg border border-red-200 px-3 py-1.5 text-xs font-semibold text-red-500 transition hover:bg-red-50"
                          onClick={(e) => {
                            if (!confirm(`Hapus brand "${brand.name}"?`)) e.preventDefault();
                          }}
                        >
                          Hapus
                        </button>
                      </form>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
