import Link from "next/link";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { Stars } from "@/components/StarRating";
import { setReviewStatus, upsertAdminReply } from "@/lib/reviews";
import { getSession } from "@/lib/auth";
import { redirect } from "next/navigation";
import type { ReviewStatus } from "@prisma/client";

const PAGE_SIZE = 20;

export default async function AdminReviewsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; page?: string }>;
}) {
  const session = await getSession();
  if (!session || session.role !== "ADMIN") redirect("/admin/login");

  const { status, page: pageStr } = await searchParams;
  const page = Math.max(1, Number(pageStr) || 1);
  const filterStatus =
    status === "VISIBLE" || status === "HIDDEN" || status === "DELETED"
      ? (status as ReviewStatus)
      : null;

  const where = filterStatus ? { status: filterStatus } : {};

  const [reviews, total, counts] = await Promise.all([
    prisma.review.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * PAGE_SIZE,
      take: PAGE_SIZE,
      include: {
        user: { select: { name: true, email: true } },
        product: { select: { name: true, slug: true, imageUrl: true } },
        images: { orderBy: { position: "asc" } },
        reply: true,
      },
    }),
    prisma.review.count({ where }),
    prisma.review.groupBy({
      by: ["status"],
      _count: true,
    }),
  ]);

  const totalPages = Math.ceil(total / PAGE_SIZE);
  const countByStatus: Record<string, number> = {};
  for (const c of counts) countByStatus[c.status] = c._count;

  // ── Server actions ──────────────────────────────────────────
  async function hideReview(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    const reason = String(formData.get("reason") ?? "Konten tidak sesuai");
    await setReviewStatus(id, "HIDDEN", reason);
    revalidatePath("/admin/reviews");
  }

  async function unhideReview(formData: FormData) {
    "use server";
    const id = String(formData.get("id"));
    await setReviewStatus(id, "VISIBLE");
    revalidatePath("/admin/reviews");
  }

  async function submitReply(formData: FormData) {
    "use server";
    const id = String(formData.get("reviewId"));
    const content = String(formData.get("content") ?? "");
    const sess = await getSession();
    if (!sess || sess.role !== "ADMIN") return;
    await upsertAdminReply(id, sess.sub, content);
    revalidatePath("/admin/reviews");
  }

  const tabs: Array<{ key: string; label: string; count: number }> = [
    { key: "all", label: "Semua", count: total },
    { key: "VISIBLE", label: "Tampil", count: countByStatus.VISIBLE ?? 0 },
    { key: "HIDDEN", label: "Disembunyikan", count: countByStatus.HIDDEN ?? 0 },
    { key: "DELETED", label: "Dihapus user", count: countByStatus.DELETED ?? 0 },
  ];

  return (
    <div className="mx-auto max-w-6xl px-4 py-10">
      <Link href="/admin" className="text-sm font-bold text-zinc-500 hover:text-zinc-950">
        ← Kembali ke dashboard
      </Link>
      <h1 className="mt-2 text-3xl font-black tracking-tight text-zinc-950">Moderasi Review</h1>
      <p className="mt-1 text-sm text-zinc-500">
        Kelola review pembeli dari pelanggan toko.
      </p>

      {/* Filter tabs */}
      <div className="mt-6 flex flex-wrap gap-2">
        {tabs.map((t) => {
          const isActive = (filterStatus ?? "all") === t.key;
          const href =
            t.key === "all" ? "/admin/reviews" : `/admin/reviews?status=${t.key}`;
          return (
            <Link
              key={t.key}
              href={href}
              className={`flex items-center gap-2 rounded-full border px-4 py-2 text-sm font-semibold transition ${
                isActive
                  ? "border-zinc-950 bg-zinc-950 text-white"
                  : "border-zinc-200 bg-white text-zinc-600 hover:border-zinc-400"
              }`}
            >
              {t.label}
              <span
                className={`rounded-full px-2 py-0.5 text-[11px] font-bold ${
                  isActive ? "bg-white/20 text-white" : "bg-zinc-100 text-zinc-700"
                }`}
              >
                {t.count}
              </span>
            </Link>
          );
        })}
      </div>

      {/* Review list */}
      <div className="mt-6 space-y-4">
        {reviews.length === 0 ? (
          <div className="rounded-2xl border border-zinc-200 bg-white p-12 text-center">
            <p className="text-zinc-500">Belum ada review.</p>
          </div>
        ) : (
          reviews.map((r) => (
            <div
              key={r.id}
              className={`rounded-2xl border bg-white p-5 ${
                r.status === "HIDDEN"
                  ? "border-red-200 bg-red-50"
                  : r.status === "DELETED"
                  ? "border-gray-200 bg-gray-50 opacity-70"
                  : "border-zinc-100"
              }`}
            >
              {/* Header */}
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="flex items-center gap-3">
                  <div className="h-12 w-12 shrink-0 overflow-hidden rounded-lg bg-zinc-100">
                    {r.product.imageUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={r.product.imageUrl}
                        alt=""
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <div className="flex h-full items-center justify-center text-xl">🐾</div>
                    )}
                  </div>
                  <div>
                    <Link
                      href={`/products/${r.product.slug}`}
                      className="text-sm font-semibold text-zinc-950 hover:text-natalo-700"
                    >
                      {r.product.name}
                    </Link>
                    <p className="text-xs text-zinc-400">
                      {r.user.name} · {r.user.email ?? "—"}
                    </p>
                  </div>
                </div>
                <span
                  className={`rounded-full px-3 py-1 text-xs font-bold ${
                    r.status === "VISIBLE"
                      ? "bg-green-100 text-green-700"
                      : r.status === "HIDDEN"
                      ? "bg-red-100 text-red-700"
                      : "bg-zinc-200 text-zinc-600"
                  }`}
                >
                  {r.status}
                </span>
              </div>

              {/* Body */}
              <div className="mt-3 flex items-center gap-3">
                <Stars rating={r.rating} size="sm" />
                <span className="text-xs text-zinc-400">
                  {new Date(r.createdAt).toLocaleString("id-ID")}
                </span>
                {r.variantLabel && (
                  <span className="rounded-full bg-natalo-50 px-2 py-0.5 text-xs font-semibold text-natalo-700">
                    {r.variantLabel}
                  </span>
                )}
              </div>
              {r.title && <p className="mt-3 font-semibold text-zinc-950">{r.title}</p>}
              {r.content && <p className="mt-2 text-sm text-zinc-700 whitespace-pre-line">{r.content}</p>}
              {r.images.length > 0 && (
                <div className="mt-3 flex flex-wrap gap-2">
                  {r.images.map((img) => (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      key={img.id}
                      src={img.imageUrl}
                      alt=""
                      className="h-16 w-16 rounded-lg object-cover"
                    />
                  ))}
                </div>
              )}
              {r.hiddenReason && (
                <p className="mt-2 text-xs text-red-600">Alasan disembunyikan: {r.hiddenReason}</p>
              )}

              {/* Existing reply */}
              {r.reply && (
                <div className="mt-3 rounded-xl bg-natalo-50 p-3">
                  <p className="text-xs font-bold text-natalo-800">Balasan saat ini:</p>
                  <p className="mt-1 text-sm text-zinc-700 whitespace-pre-line">{r.reply.content}</p>
                </div>
              )}

              {/* Actions */}
              <div className="mt-4 flex flex-wrap gap-2">
                {r.status === "VISIBLE" ? (
                  <form action={hideReview}>
                    <input type="hidden" name="id" value={r.id} />
                    <input type="hidden" name="reason" value="Konten tidak sesuai kebijakan toko" />
                    <button
                      type="submit"
                      className="rounded-full border border-red-300 bg-white px-4 py-1.5 text-xs font-bold text-red-600 hover:bg-red-50"
                    >
                      Sembunyikan
                    </button>
                  </form>
                ) : r.status === "HIDDEN" ? (
                  <form action={unhideReview}>
                    <input type="hidden" name="id" value={r.id} />
                    <button
                      type="submit"
                      className="rounded-full border border-green-300 bg-white px-4 py-1.5 text-xs font-bold text-green-600 hover:bg-green-50"
                    >
                      Tampilkan
                    </button>
                  </form>
                ) : null}

                <details className="inline-block">
                  <summary className="cursor-pointer rounded-full border border-zinc-300 px-4 py-1.5 text-xs font-bold text-zinc-700 hover:bg-zinc-50">
                    {r.reply ? "Edit balasan" : "Balas"}
                  </summary>
                  <form action={submitReply} className="mt-2 flex gap-2">
                    <input type="hidden" name="reviewId" value={r.id} />
                    <textarea
                      name="content"
                      defaultValue={r.reply?.content ?? ""}
                      placeholder="Tulis balasan..."
                      required
                      rows={2}
                      className="w-full max-w-md rounded-xl border border-zinc-300 px-3 py-2 text-sm outline-none focus:border-zinc-950"
                    />
                    <button
                      type="submit"
                      className="self-start rounded-full bg-natalo-600 px-4 py-2 text-xs font-bold text-white hover:bg-natalo-700"
                    >
                      Kirim
                    </button>
                  </form>
                </details>
              </div>
            </div>
          ))
        )}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="mt-6 flex items-center justify-between">
          <p className="text-sm text-zinc-500">
            Halaman {page} dari {totalPages} · {total} review
          </p>
          <div className="flex gap-2">
            {page > 1 && (
              <Link
                href={`/admin/reviews?${filterStatus ? `status=${filterStatus}&` : ""}page=${page - 1}`}
                className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-bold hover:bg-zinc-50"
              >
                ← Sebelumnya
              </Link>
            )}
            {page < totalPages && (
              <Link
                href={`/admin/reviews?${filterStatus ? `status=${filterStatus}&` : ""}page=${page + 1}`}
                className="rounded-full bg-zinc-950 px-4 py-2 text-sm font-bold text-white hover:bg-zinc-800"
              >
                Selanjutnya →
              </Link>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
