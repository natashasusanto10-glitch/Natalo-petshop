import Link from "next/link";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { Stars } from "@/components/StarRating";
import { setReviewStatus, upsertAdminReply } from "@/lib/reviews";
import { getSession } from "@/lib/auth";
import { redirect } from "next/navigation";
import type { ReviewStatus } from "@prisma/client";
import {
  PageHeader,
  EmptyState,
  Badge,
  Button,
  AdminPage,
  Pagination,
  type BadgeVariant,
} from "@/components/admin/ui";
import { reviewStatusLabel } from "@/lib/order-labels";

const REVIEW_STATUS_VARIANT: Record<string, BadgeVariant> = {
  VISIBLE: "success",
  HIDDEN: "danger",
  DELETED: "neutral",
};

const PAGE_SIZE = 20;

export default async function AdminReviewsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; page?: string }>;
}) {
  const session = await getSession("ADMIN");
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
    const sess = await getSession("ADMIN");
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
    <AdminPage maxWidth="xl">
      <PageHeader
        title="Moderasi Review"
        subtitle={`Kelola ${total} review pembeli — approve, hide, atau balas.`}
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            ← Dashboard
          </Button>
        }
      />

      {/* Filter tabs */}
      <div className="-mx-4 mt-5 flex gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:mt-6 md:flex-wrap md:overflow-visible md:px-0">
        {tabs.map((t) => {
          const isActive = (filterStatus ?? "all") === t.key;
          const href =
            t.key === "all" ? "/admin/reviews" : `/admin/reviews?status=${t.key}`;
          return (
            <Link
              key={t.key}
              href={href}
              className={`flex shrink-0 items-center gap-2 rounded-full border px-4 py-2 text-sm font-semibold transition ${
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
          <div className="rounded-2xl border border-zinc-200 bg-white">
            <EmptyState
              icon="⭐"
              title="Belum ada review"
              description={
                filterStatus
                  ? "Tidak ada review dengan status ini. Coba ganti filter."
                  : "Customer akan kasih review setelah order DELIVERED."
              }
              size="full"
            />
          </div>
        ) : (
          reviews.map((r) => (
            <div
              key={r.id}
              className={`rounded-2xl border bg-white p-4 md:p-5 ${
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
                        alt={r.product.name}
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
                    <p className="text-xs text-zinc-600">
                      {r.user.name} · {r.user.email ?? "—"}
                    </p>
                  </div>
                </div>
                <Badge
                  variant={REVIEW_STATUS_VARIANT[r.status] ?? "neutral"}
                  size="md"
                >
                  {reviewStatusLabel(r.status)}
                </Badge>
              </div>

              {/* Body */}
              <div className="mt-3 flex items-center gap-3">
                <Stars rating={r.rating} size="sm" />
                <span className="text-xs text-zinc-600">
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
                      alt={`Foto ulasan ${r.product.name}`}
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
                    <Button type="submit" variant="dangerSoft" size="sm">
                      Sembunyikan
                    </Button>
                  </form>
                ) : r.status === "HIDDEN" ? (
                  <form action={unhideReview}>
                    <input type="hidden" name="id" value={r.id} />
                    <Button type="submit" variant="secondary" size="sm">
                      Tampilkan
                    </Button>
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
                    <Button type="submit" size="sm" className="self-start">
                      Kirim
                    </Button>
                  </form>
                </details>
              </div>
            </div>
          ))
        )}
      </div>

      {/* Pagination */}
      <Pagination
        currentPage={page}
        totalPages={totalPages}
        hrefFor={(target) =>
          `/admin/reviews?${filterStatus ? `status=${filterStatus}&` : ""}page=${target}`
        }
        summary={`${total} review`}
      />
    </AdminPage>
  );
}
