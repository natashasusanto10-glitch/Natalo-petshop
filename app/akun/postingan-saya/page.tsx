import type { Metadata } from "next";
import Link from "next/link";
import type { Prisma } from "@prisma/client";
import {
  FiArrowLeft,
  FiInfo,
  FiPlayCircle,
  FiPlus,
} from "react-icons/fi";
import {
  MyFeedPostsList,
  type MyFeedPostListItem,
} from "@/components/feed/MyFeedPostsList";
import { prisma } from "@/lib/prisma";
import { requireCustomerSession } from "@/lib/session-guards";
import {
  MY_FEED_STATUS_BY_FILTER,
  MY_FEED_VISIBLE_STATUSES,
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
  searchParams: Promise<{ status?: string; deleted?: string }>;
};

function deletedSuccessCopy(value: string | undefined) {
  if (value === "pending") {
    return {
      title: "Postingan berhasil dihapus",
      message: "Video tidak lagi masuk proses review.",
    };
  }
  if (value === "rejected") {
    return {
      title: "Postingan berhasil dihapus",
      message: "Postingan yang ditolak sudah dihapus dari daftar Postingan Saya.",
    };
  }
  if (value === "active") {
    return {
      title: "Video berhasil dihapus",
      message: "Video tidak lagi tampil di Feed.",
    };
  }
  return null;
}

export default async function MyFeedPostsPage({ searchParams }: PageProps) {
  const [{ status, deleted }, session] = await Promise.all([
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

  const posts: MyFeedPostListItem[] = rawPosts.map((post) => ({
    ...post,
    createdAt: post.createdAt.toISOString(),
  }));
  const isCompletelyEmpty = totalCount === 0;
  const deleteSuccess = deletedSuccessCopy(deleted);

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

        {deleteSuccess && (
          <section className="flex items-start gap-3 rounded-[18px] border border-emerald-100 bg-emerald-50 p-3 text-emerald-900 shadow-[0_8px_24px_rgba(16,24,40,0.04)]">
            <span className="mt-0.5 grid h-7 w-7 shrink-0 place-items-center rounded-full bg-white text-emerald-600">
              <FiPlayCircle className="h-4 w-4" aria-hidden="true" />
            </span>
            <span>
              <span className="block text-sm font-black">{deleteSuccess.title}</span>
              <span className="mt-0.5 block text-xs font-semibold leading-5">
                {deleteSuccess.message}
              </span>
            </span>
          </section>
        )}

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
          <MyFeedPostsList posts={posts} />
        )}
      </div>
    </main>
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
