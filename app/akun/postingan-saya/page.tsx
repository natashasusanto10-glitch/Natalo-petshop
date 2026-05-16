import type { Metadata } from "next";
import Link from "next/link";
import type { FeedPostStatus, Prisma } from "@prisma/client";
import {
  FiArrowLeft,
  FiHeart,
  FiInfo,
  FiMessageCircle,
  FiMoreVertical,
  FiPlay,
  FiPlayCircle,
  FiPlus,
  FiShare2,
  FiVideo,
} from "react-icons/fi";
import { prisma } from "@/lib/prisma";
import { requireCustomerSession } from "@/lib/session-guards";
import {
  formatFeedDuration,
  formatFeedPostDate,
  MY_FEED_STATUS_BY_FILTER,
  MY_FEED_VISIBLE_STATUSES,
  myFeedStatusMeta,
  normalizeMyFeedFilter,
  type MyFeedFilter,
} from "@/lib/feed/my-posts";

export const metadata: Metadata = {
  title: "Postingan Saya",
  robots: { index: false, follow: false },
};

const FILTERS: Array<{ key: MyFeedFilter; label: string }> = [
  { key: "all", label: "Semua" },
  { key: "pending", label: "Menunggu Review" },
  { key: "active", label: "Tayang" },
  { key: "rejected", label: "Ditolak" },
];

type PageProps = {
  searchParams: Promise<{ status?: string }>;
};

type MyPostCardData = {
  id: string;
  title: string;
  description: string | null;
  thumbnailUrl: string | null;
  videoDurationSec: number | null;
  createdAt: Date;
  status: FeedPostStatus;
  moderationNote: string | null;
  likeCount: number;
  commentCount: number;
  shareCount: number;
};

function displayCaption(post: Pick<MyPostCardData, "title" | "description">) {
  const caption = post.description?.split("\n\n")[0]?.trim();
  return caption || post.title || "Postingan baru";
}

export default async function MyFeedPostsPage({ searchParams }: PageProps) {
  const [{ status }, session] = await Promise.all([
    searchParams,
    requireCustomerSession(),
  ]);
  const filter = normalizeMyFeedFilter(status);
  const selectedStatus =
    filter === "all" ? undefined : MY_FEED_STATUS_BY_FILTER[filter];

  const baseWhere: Prisma.FeedPostWhereInput = {
    authorId: session.sub,
    authorRole: "CUSTOMER",
    kind: "COMMUNITY",
    deletedAt: null,
    status: { in: [...MY_FEED_VISIBLE_STATUSES] },
  };
  const where: Prisma.FeedPostWhereInput = {
    ...baseWhere,
    status: selectedStatus ?? { in: [...MY_FEED_VISIBLE_STATUSES] },
  };

  const [rawPosts, totalCount] = await Promise.all([
    prisma.feedPost.findMany({
      where,
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      select: {
        id: true,
        title: true,
        description: true,
        thumbnailUrl: true,
        videoDurationSec: true,
        createdAt: true,
        status: true,
        moderationNote: true,
        likeCount: true,
        commentCount: true,
        shareCount: true,
      },
    }),
    prisma.feedPost.count({ where: baseWhere }),
  ]);

  const posts: MyPostCardData[] = rawPosts;
  const isCompletelyEmpty = totalCount === 0;

  return (
    <main className="min-h-screen bg-slate-50 pb-6">
      <header className="sticky top-0 z-20 border-b border-slate-100/80 bg-slate-50/95 px-4 pb-3 pt-[calc(env(safe-area-inset-top)+0.75rem)] backdrop-blur">
        <div className="relative mx-auto flex h-10 max-w-4xl items-center justify-center">
          <Link
            href="/member"
            className="absolute left-0 grid h-10 w-10 place-items-center rounded-full text-slate-900 transition active:bg-white"
            aria-label="Kembali ke akun"
          >
            <FiArrowLeft className="h-5 w-5" aria-hidden="true" />
          </Link>
          <h1 className="text-base font-black text-slate-950">Postingan Saya</h1>
        </div>
      </header>

      <div className="mx-auto max-w-4xl space-y-4 px-4 pt-4">
        <nav
          aria-label="Filter status postingan"
          className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        >
          {FILTERS.map((item) => {
            const active = item.key === filter;
            return (
              <Link
                key={item.key}
                href={
                  item.key === "all"
                    ? "/akun/postingan-saya"
                    : `/akun/postingan-saya?status=${item.key}`
                }
                className={`shrink-0 rounded-full px-4 py-2 text-xs font-black ring-1 transition active:scale-[0.98] ${
                  active
                    ? "bg-natalo-600 text-white ring-natalo-600 shadow-[0_8px_18px_rgba(30,95,191,0.22)]"
                    : "bg-white text-slate-600 ring-slate-200"
                }`}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>

        <section className="flex items-start gap-3 rounded-[18px] border border-slate-200 bg-white p-3 text-slate-700 shadow-[0_8px_24px_rgba(16,24,40,0.05)]">
          <span className="mt-0.5 grid h-7 w-7 shrink-0 place-items-center rounded-full bg-natalo-50 text-natalo-700">
            <FiInfo className="h-4 w-4" aria-hidden="true" />
          </span>
          <p className="text-xs font-semibold leading-5">
            Postingan kamu hanya bisa dilihat oleh kamu. Jika disetujui, video
            akan otomatis tampil di Feed.
          </p>
        </section>

        {isCompletelyEmpty ? (
          <EmptyState />
        ) : posts.length === 0 ? (
          <section className="rounded-[22px] border border-slate-100 bg-white p-6 text-center shadow-[0_8px_24px_rgba(16,24,40,0.05)]">
            <p className="text-sm font-black text-slate-950">
              Tidak ada postingan di filter ini
            </p>
            <p className="mt-1 text-xs font-semibold leading-5 text-slate-500">
              Coba pilih status lain untuk melihat postingan kamu.
            </p>
          </section>
        ) : (
          <>
            <section className="space-y-3">
              {posts.map((post) => (
                <PostCard key={post.id} post={post} />
              ))}
            </section>
            <div className="sticky bottom-0 z-10 -mx-4 bg-gradient-to-t from-slate-50 via-slate-50 to-slate-50/0 px-4 pb-[calc(env(safe-area-inset-bottom)+0.75rem)] pt-4">
              <Link
                href="/feed/upload"
                className="flex w-full items-center justify-center gap-2 rounded-2xl bg-natalo-600 px-4 py-3.5 text-sm font-black text-white shadow-[0_10px_24px_rgba(30,95,191,0.28)] transition active:scale-[0.98]"
              >
                Upload Video
                <FiPlus className="h-5 w-5" aria-hidden="true" />
              </Link>
            </div>
          </>
        )}
      </div>
    </main>
  );
}

function PostCard({ post }: { post: MyPostCardData }) {
  const meta = myFeedStatusMeta(post.status);
  const caption = displayCaption(post);

  return (
    <Link
      href={`/akun/postingan-saya/${post.id}`}
      className="flex gap-3 rounded-[22px] border border-slate-100 bg-white p-3 shadow-[0_8px_24px_rgba(16,24,40,0.06)] transition active:scale-[0.99]"
    >
      <PostThumbnail
        src={post.thumbnailUrl}
        duration={formatFeedDuration(post.videoDurationSec)}
      />
      <span className="min-w-0 flex-1 py-1">
        <span className="flex items-start gap-2">
          <span className="line-clamp-2 min-w-0 flex-1 text-sm font-black leading-5 text-slate-950">
            {caption}
          </span>
          <FiMoreVertical className="mt-0.5 h-4 w-4 shrink-0 text-slate-400" aria-hidden="true" />
        </span>
        <span className="mt-1 block text-xs font-semibold text-slate-500">
          {formatFeedPostDate(post.createdAt)}
        </span>
        <span
          className={`mt-2 inline-flex rounded-full px-2.5 py-1 text-[11px] font-black ring-1 ${meta.badgeClass}`}
        >
          {meta.label}
        </span>
        <span className="mt-2 block text-xs font-semibold leading-5 text-slate-600">
          {meta.description}
        </span>
        {post.status === "REJECTED" && (
          <span className="mt-1 block text-xs font-semibold leading-5 text-slate-600">
            Alasan: {post.moderationNote?.trim() || "Alasan penolakan belum tersedia."}
          </span>
        )}
        {post.status === "ACTIVE" && (
          <span className="mt-3 flex flex-wrap items-center gap-4 text-xs font-bold text-slate-500">
            <span className="inline-flex items-center gap-1">
              <FiHeart className="h-4 w-4" aria-hidden="true" />
              {post.likeCount}
            </span>
            <span className="inline-flex items-center gap-1">
              <FiMessageCircle className="h-4 w-4" aria-hidden="true" />
              {post.commentCount}
            </span>
            <span className="inline-flex items-center gap-1">
              <FiShare2 className="h-4 w-4" aria-hidden="true" />
              {post.shareCount}
            </span>
          </span>
        )}
      </span>
    </Link>
  );
}

function PostThumbnail({ src, duration }: { src: string | null; duration: string }) {
  return (
    <span className="relative block h-[150px] w-[112px] shrink-0 overflow-hidden rounded-2xl bg-slate-900">
      {src ? (
        <img
          src={src}
          alt=""
          loading="lazy"
          className="h-full w-full object-cover"
        />
      ) : (
        <span className="grid h-full w-full place-items-center bg-[linear-gradient(135deg,#eff6ff_0%,#dbeafe_48%,#0f4eaf_100%)] text-white">
          <FiVideo className="h-9 w-9 drop-shadow" aria-hidden="true" />
        </span>
      )}
      <span className="absolute inset-0 bg-black/10" aria-hidden="true" />
      <span className="absolute inset-0 grid place-items-center" aria-hidden="true">
        <span className="grid h-10 w-10 place-items-center rounded-full bg-black/55 text-white backdrop-blur-sm">
          <FiPlay className="ml-0.5 h-5 w-5" />
        </span>
      </span>
      <span className="absolute bottom-2 left-2 rounded-md bg-black/70 px-2 py-0.5 text-[11px] font-black text-white">
        {duration}
      </span>
    </span>
  );
}

function EmptyState() {
  return (
    <section className="rounded-[24px] border border-slate-100 bg-white p-7 text-center shadow-[0_8px_24px_rgba(16,24,40,0.05)]">
      <span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-natalo-50 text-natalo-700">
        <FiPlayCircle className="h-7 w-7" aria-hidden="true" />
      </span>
      <h2 className="mt-4 text-base font-black text-slate-950">
        Belum ada postingan
      </h2>
      <p className="mt-1 text-sm font-semibold leading-5 text-slate-500">
        Upload video pertama kamu ke NL Feed.
      </p>
      <Link
        href="/feed/upload"
        className="mt-5 inline-flex items-center justify-center gap-2 rounded-2xl bg-natalo-600 px-5 py-3 text-sm font-black text-white shadow-[0_10px_24px_rgba(30,95,191,0.28)] transition active:scale-[0.98]"
      >
        Upload Video
        <FiPlus className="h-5 w-5" aria-hidden="true" />
      </Link>
    </section>
  );
}
