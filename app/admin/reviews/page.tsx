import { prisma } from "@/lib/prisma";
import { revalidatePath } from "next/cache";

async function approveReview(formData: FormData) {
  "use server";
  const id = formData.get("id") as string;
  await prisma.review.update({ where: { id }, data: { isApproved: true } });
  revalidatePath("/admin/reviews");
}

async function deleteReview(formData: FormData) {
  "use server";
  const id = formData.get("id") as string;
  await prisma.review.delete({ where: { id } }).catch(() => {});
  revalidatePath("/admin/reviews");
}

export default async function AdminReviewsPage() {
  const [pending, approved] = await Promise.all([
    prisma.review.findMany({
      where: { isApproved: false },
      orderBy: { createdAt: "desc" },
      include: { product: { select: { name: true } } },
    }).catch(() => []),
    prisma.review.findMany({
      where: { isApproved: true },
      orderBy: { createdAt: "desc" },
      take: 50,
      include: { product: { select: { name: true } } },
    }).catch(() => []),
  ]);

  function StarRow({ rating }: { rating: number }) {
    return (
      <span className="text-sm">
        {[1, 2, 3, 4, 5].map((s) => (
          <span key={s} className={rating >= s ? "text-orange-400" : "text-gray-200"}>★</span>
        ))}
      </span>
    );
  }

  return (
    <div className="mx-auto max-w-5xl px-4 py-6 lg:py-10">
      <div>
        <h1 className="text-2xl font-black tracking-tight text-zinc-950 lg:text-3xl">Review Produk</h1>
        <p className="mt-1 text-sm text-zinc-500">Moderasi ulasan produk dari customer.</p>
      </div>

      {/* Pending */}
      <section className="mt-8">
        <h2 className="flex items-center gap-2 font-bold text-zinc-900">
          Menunggu Moderasi
          {pending.length > 0 && (
            <span className="rounded-full bg-orange-500 px-2.5 py-0.5 text-xs font-bold text-white">{pending.length}</span>
          )}
        </h2>

        {pending.length === 0 ? (
          <p className="mt-4 text-sm text-zinc-400">Tidak ada ulasan yang menunggu moderasi.</p>
        ) : (
          <div className="mt-4 space-y-3">
            {pending.map((r) => (
              <div key={r.id} className="rounded-2xl border border-orange-100 bg-orange-50 p-4">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="flex-1">
                    <p className="font-semibold text-zinc-900">{r.name}</p>
                    <StarRow rating={r.rating} />
                    <p className="mt-1 text-xs text-zinc-400">
                      Produk: {r.product?.name ?? "—"} ·{" "}
                      {new Date(r.createdAt).toLocaleDateString("id-ID", { day: "numeric", month: "short", year: "numeric" })}
                    </p>
                    <p className="mt-2 text-sm text-zinc-700">{r.comment}</p>
                  </div>
                  <div className="flex gap-2">
                    <form action={approveReview}>
                      <input type="hidden" name="id" value={r.id} />
                      <button type="submit" className="rounded-full bg-green-500 px-4 py-2 text-xs font-bold text-white transition hover:bg-green-600">
                        Setujui
                      </button>
                    </form>
                    <form action={deleteReview}>
                      <input type="hidden" name="id" value={r.id} />
                      <button type="submit" className="rounded-full border border-red-200 px-4 py-2 text-xs font-bold text-red-500 transition hover:bg-red-50">
                        Hapus
                      </button>
                    </form>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Approved */}
      <section className="mt-10">
        <h2 className="font-bold text-zinc-900">Ulasan Disetujui ({approved.length})</h2>
        {approved.length === 0 ? (
          <p className="mt-4 text-sm text-zinc-400">Belum ada ulasan yang disetujui.</p>
        ) : (
          <div className="mt-4 rounded-2xl border border-zinc-200 bg-white overflow-hidden">
            <table className="w-full text-sm">
              <thead className="border-b border-zinc-100 bg-zinc-50">
                <tr>
                  <th className="px-4 py-3 text-left font-semibold text-zinc-500">Nama</th>
                  <th className="px-4 py-3 text-left font-semibold text-zinc-500">Produk</th>
                  <th className="px-4 py-3 text-left font-semibold text-zinc-500">Rating</th>
                  <th className="px-4 py-3 text-left font-semibold text-zinc-500">Ulasan</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-100">
                {approved.map((r) => (
                  <tr key={r.id} className="hover:bg-zinc-50">
                    <td className="px-4 py-3 font-semibold text-zinc-900">{r.name}</td>
                    <td className="px-4 py-3 text-zinc-500">{r.product?.name ?? "—"}</td>
                    <td className="px-4 py-3"><StarRow rating={r.rating} /></td>
                    <td className="px-4 py-3 text-zinc-600 max-w-xs truncate">{r.comment}</td>
                    <td className="px-4 py-3 text-right">
                      <form action={deleteReview}>
                        <input type="hidden" name="id" value={r.id} />
                        <button type="submit" className="rounded-lg border border-red-200 px-3 py-1.5 text-xs font-semibold text-red-500 hover:bg-red-50">
                          Hapus
                        </button>
                      </form>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
