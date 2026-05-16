import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import type { ReactNode } from "react";
import {
  FiArrowLeft,
  FiCalendar,
  FiClock,
  FiHash,
  FiPackage,
  FiPlay,
  FiVideo,
} from "react-icons/fi";
import { MyFeedPostActions } from "@/components/feed/MyFeedPostsList";
import { prisma } from "@/lib/prisma";
import { requireCustomerSession } from "@/lib/session-guards";
import {
  formatFeedDuration,
  formatFeedPostDate,
  MY_FEED_VISIBLE_STATUSES,
  myFeedStatusMeta,
} from "@/lib/feed/my-posts";

export const metadata: Metadata = {
  title: "Detail Postingan",
  robots: { index: false, follow: false },
};

type PageProps = {
  params: Promise<{ id: string }>;
};

function displayCaption(post: { title: string; description: string | null }) {
  const caption = post.description?.split("\n\n")[0]?.trim();
  return caption || post.title || "Postingan baru";
}

export default async function MyFeedPostDetailPage({ params }: PageProps) {
  const [{ id }, session] = await Promise.all([
    params,
    requireCustomerSession(),
  ]);

  const post = await prisma.feedPost.findFirst({
    where: {
      id,
      authorId: session.sub,
      authorRole: "CUSTOMER",
      kind: "COMMUNITY",
      deletedAt: null,
      status: { in: [...MY_FEED_VISIBLE_STATUSES] },
    },
    include: {
      product: {
        select: {
          id: true,
          slug: true,
          name: true,
          imageUrl: true,
          category: {
            select: {
              id: true,
              name: true,
              slug: true,
            },
          },
        },
      },
    },
  });

  if (!post) notFound();

  const caption = displayCaption(post);
  const statusMeta = myFeedStatusMeta(post.status);
  const categoryName = post.product?.category?.name ?? null;

  return (
    <main className="min-h-screen bg-slate-50 pb-6">
      <header className="sticky top-0 z-20 border-b border-slate-100/80 bg-slate-50/95 px-4 pb-3 pt-[calc(env(safe-area-inset-top)+0.75rem)] backdrop-blur">
        <div className="relative mx-auto flex h-10 max-w-4xl items-center justify-center">
          <Link
            href="/akun/postingan-saya"
            className="absolute left-0 grid h-10 w-10 place-items-center rounded-full text-slate-900 transition active:bg-white"
            aria-label="Kembali ke Postingan Saya"
          >
            <FiArrowLeft className="h-5 w-5" aria-hidden="true" />
          </Link>
          <h1 className="text-base font-black text-slate-950">Detail Postingan</h1>
          <MyFeedPostActions
            postId={post.id}
            status={post.status}
            detailHref={`/akun/postingan-saya/${post.id}`}
            source="detail"
            triggerClassName="absolute right-0 grid h-10 w-10 place-items-center rounded-full text-slate-900 transition active:bg-white"
          />
        </div>
      </header>

      <div className="mx-auto max-w-4xl space-y-4 px-4 pt-4">
        <MediaPreview
          videoUrl={post.videoUrl}
          thumbnailUrl={post.thumbnailUrl}
          caption={caption}
          duration={formatFeedDuration(post.videoDurationSec)}
        />

        <section className="rounded-[22px] border border-slate-100 bg-white p-4 shadow-[0_8px_24px_rgba(16,24,40,0.06)]">
          <h2 className="text-base font-black leading-6 text-slate-950">
            {caption}
          </h2>
          <p className="mt-1 flex items-center gap-1.5 text-xs font-semibold text-slate-500">
            <FiCalendar className="h-4 w-4" aria-hidden="true" />
            {formatFeedPostDate(post.createdAt)}
          </p>

          <div className={`mt-4 rounded-2xl border p-3 ${statusMeta.panelClass}`}>
            <span
              className={`inline-flex rounded-full px-2.5 py-1 text-[11px] font-black ring-1 ${statusMeta.badgeClass}`}
            >
              {statusMeta.label}
            </span>
            <p className="mt-2 text-xs font-semibold leading-5">
              {statusMeta.description}
              {post.status === "PENDING_REVIEW"
                ? ". Jika disetujui, video akan otomatis tampil di Feed."
                : ""}
            </p>
            {post.status === "REJECTED" && (
              <p className="mt-2 text-xs font-semibold leading-5">
                Alasan: {post.moderationNote?.trim() || "Alasan penolakan belum tersedia."}
              </p>
            )}
          </div>
        </section>

        <section className="overflow-hidden rounded-[22px] border border-slate-100 bg-white shadow-[0_8px_24px_rgba(16,24,40,0.06)]">
          <h2 className="border-b border-slate-100 px-4 py-3 text-sm font-black text-slate-950">
            Informasi Video
          </h2>
          <div className="divide-y divide-slate-100">
            <InfoRow
              icon={<FiClock className="h-4 w-4" aria-hidden="true" />}
              label="Durasi"
              value={formatFeedDuration(post.videoDurationSec)}
            />
            <InfoRow
              icon={<FiPlay className="h-4 w-4" aria-hidden="true" />}
              label="Status review"
              value={statusMeta.label}
            />
            {categoryName && (
              <InfoRow
                icon={<FiHash className="h-4 w-4" aria-hidden="true" />}
                label="Kategori"
                value={categoryName}
              />
            )}
            {post.product && (
              <InfoRow
                icon={<FiPackage className="h-4 w-4" aria-hidden="true" />}
                label="Produk disematkan"
                value={post.product.name}
                imageUrl={post.product.imageUrl}
              />
            )}
          </div>
        </section>
      </div>
    </main>
  );
}

function MediaPreview({
  videoUrl,
  thumbnailUrl,
  caption,
  duration,
}: {
  videoUrl: string | null;
  thumbnailUrl: string | null;
  caption: string;
  duration: string;
}) {
  return (
    <section className="overflow-hidden rounded-[22px] bg-slate-950 shadow-[0_12px_28px_rgba(16,24,40,0.14)]">
      <div className="relative aspect-video w-full bg-slate-900">
        {videoUrl ? (
          <video
            src={videoUrl}
            poster={thumbnailUrl ?? undefined}
            controls
            playsInline
            preload="metadata"
            className="h-full w-full object-cover"
          />
        ) : thumbnailUrl ? (
          <img
            src={thumbnailUrl}
            alt={caption}
            className="h-full w-full object-cover"
          />
        ) : (
          <span className="grid h-full w-full place-items-center bg-[linear-gradient(135deg,#eff6ff_0%,#dbeafe_48%,#0f4eaf_100%)] text-white">
            <FiVideo className="h-12 w-12 drop-shadow" aria-hidden="true" />
          </span>
        )}
        <span className="pointer-events-none absolute inset-0 bg-black/10" aria-hidden="true" />
        <span className="pointer-events-none absolute inset-0 grid place-items-center" aria-hidden="true">
          <span className="grid h-14 w-14 place-items-center rounded-full bg-black/50 text-white backdrop-blur-sm">
            <FiPlay className="ml-1 h-7 w-7" />
          </span>
        </span>
        <span className="absolute bottom-3 right-3 rounded-md bg-black/75 px-2.5 py-1 text-xs font-black text-white">
          {duration}
        </span>
      </div>
    </section>
  );
}

function InfoRow({
  icon,
  label,
  value,
  imageUrl,
}: {
  icon: ReactNode;
  label: string;
  value: string;
  imageUrl?: string | null;
}) {
  return (
    <div className="flex items-center gap-3 px-4 py-3">
      <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-slate-50 text-slate-500">
        {icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-xs font-bold text-slate-500">{label}</span>
        <span className="mt-0.5 block truncate text-sm font-black text-slate-900">
          {value}
        </span>
      </span>
      {imageUrl && (
        <img
          src={imageUrl}
          alt=""
          loading="lazy"
          className="h-10 w-10 shrink-0 rounded-xl object-cover ring-1 ring-slate-100"
        />
      )}
    </div>
  );
}
