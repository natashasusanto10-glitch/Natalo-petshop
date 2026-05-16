"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import type { FeedPostStatus } from "@prisma/client";
import {
  FiCheckCircle,
  FiChevronRight,
  FiHeart,
  FiMessageCircle,
  FiMoreVertical,
  FiPlay,
  FiPlayCircle,
  FiPlus,
  FiShare2,
  FiTrash2,
  FiVideo,
  FiX,
} from "react-icons/fi";
import { BottomSheet } from "@/components/BottomSheet";
import {
  formatFeedDuration,
  formatFeedPostDate,
  myFeedStatusMeta,
} from "@/lib/feed/my-posts";

export type MyFeedPostListItem = {
  id: string;
  title: string;
  description: string | null;
  thumbnailUrl: string | null;
  videoDurationSec: number | null;
  createdAt: string;
  status: FeedPostStatus;
  moderationNote: string | null;
  likeCount: number;
  commentCount: number;
  shareCount: number;
};

type DeleteCopy = {
  actionLabel: string;
  confirmTitle: string;
  confirmMessage: string;
  confirmLabel: string;
  successTitle: string;
  successMessage: string;
  statusKey: "pending" | "active" | "rejected";
};

function displayCaption(post: Pick<MyFeedPostListItem, "title" | "description">) {
  const caption = post.description?.split("\n\n")[0]?.trim();
  return caption || post.title || "Postingan baru";
}

function deleteCopyForStatus(status: FeedPostStatus): DeleteCopy {
  if (status === "ACTIVE") {
    return {
      actionLabel: "Hapus dari Feed",
      confirmTitle: "Hapus video ini?",
      confirmMessage:
        "Video akan dihapus dari Feed dan tidak bisa dilihat pengguna lain. Jumlah like, komentar, dan share pada postingan ini juga tidak akan tampil lagi.",
      confirmLabel: "Hapus Video",
      successTitle: "Video berhasil dihapus",
      successMessage: "Video tidak lagi tampil di Feed.",
      statusKey: "active",
    };
  }

  if (status === "PENDING_REVIEW") {
    return {
      actionLabel: "Batalkan postingan",
      confirmTitle: "Batalkan postingan ini?",
      confirmMessage:
        "Video akan dihapus dari daftar postingan kamu dan tidak akan masuk proses review.",
      confirmLabel: "Hapus Postingan",
      successTitle: "Postingan berhasil dihapus",
      successMessage: "Video tidak lagi masuk proses review.",
      statusKey: "pending",
    };
  }

  return {
    actionLabel: "Hapus postingan",
    confirmTitle: "Hapus postingan ini?",
    confirmMessage: "Postingan yang ditolak akan dihapus dari daftar Postingan Saya.",
    confirmLabel: "Hapus Postingan",
    successTitle: "Postingan berhasil dihapus",
    successMessage: "Postingan yang ditolak sudah dihapus dari daftar Postingan Saya.",
    statusKey: "rejected",
  };
}

function friendlyDeleteError() {
  if (typeof navigator !== "undefined" && !navigator.onLine) {
    return "Koneksi kurang stabil. Periksa internet kamu lalu coba lagi.";
  }
  return "Video belum berhasil dihapus. Coba lagi sebentar ya.";
}

export function MyFeedPostsList({ posts }: { posts: MyFeedPostListItem[] }) {
  const router = useRouter();
  const [deletedIds, setDeletedIds] = useState<Set<string>>(() => new Set());
  const [successCopy, setSuccessCopy] = useState<DeleteCopy | null>(null);

  const visiblePosts = useMemo(
    () => posts.filter((post) => !deletedIds.has(post.id)),
    [deletedIds, posts],
  );

  function handleDeleted(postId: string, copy: DeleteCopy) {
    setDeletedIds((previous) => {
      const next = new Set(previous);
      next.add(postId);
      return next;
    });
    setSuccessCopy(copy);
    router.refresh();
  }

  return (
    <>
      {visiblePosts.length === 0 ? (
        <DeletedEmptyState />
      ) : (
        <>
          <section className="space-y-3">
            {visiblePosts.map((post) => (
              <PostCard key={post.id} post={post} onDeleted={handleDeleted} />
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

      <BottomSheet
        open={Boolean(successCopy)}
        onClose={() => setSuccessCopy(null)}
        title={successCopy?.successTitle}
      >
        <div className="space-y-4 text-center">
          <span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-emerald-50 text-emerald-600">
            <FiCheckCircle className="h-7 w-7" aria-hidden="true" />
          </span>
          <p className="text-sm font-semibold leading-6 text-slate-600">
            {successCopy?.successMessage}
          </p>
          <button
            type="button"
            onClick={() => setSuccessCopy(null)}
            className="inline-flex w-full items-center justify-center rounded-2xl bg-natalo-600 px-5 py-3 text-sm font-black text-white transition active:scale-[0.98]"
          >
            Kembali ke Postingan Saya
          </button>
        </div>
      </BottomSheet>
    </>
  );
}

function PostCard({
  post,
  onDeleted,
}: {
  post: MyFeedPostListItem;
  onDeleted: (postId: string, copy: DeleteCopy) => void;
}) {
  const meta = myFeedStatusMeta(post.status);
  const caption = displayCaption(post);
  const detailHref = `/akun/postingan-saya/${post.id}`;

  return (
    <article className="flex gap-3 rounded-[22px] border border-slate-100 bg-white p-3 shadow-[0_8px_24px_rgba(16,24,40,0.06)]">
      <Link href={detailHref} className="shrink-0 transition active:scale-[0.99]">
        <PostThumbnail
          src={post.thumbnailUrl}
          duration={
            post.videoDurationSec && post.videoDurationSec > 0
              ? formatFeedDuration(post.videoDurationSec)
              : null
          }
        />
      </Link>
      <div className="min-w-0 flex-1 py-1">
        <span className="flex items-start gap-2">
          <Link
            href={detailHref}
            className="line-clamp-2 min-w-0 flex-1 text-sm font-black leading-5 text-slate-950 transition active:text-natalo-700"
          >
            {caption}
          </Link>
          <MyFeedPostActions
            postId={post.id}
            status={post.status}
            detailHref={detailHref}
            source="list"
            onDeleted={onDeleted}
            triggerClassName="mt-[-0.25rem] grid h-9 w-9 shrink-0 place-items-center rounded-full text-slate-400 transition active:bg-slate-100"
          />
        </span>
        <Link href={detailHref} className="block">
          <span className="mt-1 block text-xs font-semibold text-slate-500">
            {formatFeedPostDate(new Date(post.createdAt))}
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
        </Link>
      </div>
    </article>
  );
}

export function MyFeedPostActions({
  postId,
  status,
  detailHref,
  source,
  triggerClassName,
  onDeleted,
}: {
  postId: string;
  status: FeedPostStatus;
  detailHref: string;
  source: "list" | "detail";
  triggerClassName?: string;
  onDeleted?: (postId: string, copy: DeleteCopy) => void;
}) {
  const router = useRouter();
  const copy = deleteCopyForStatus(status);
  const [menuOpen, setMenuOpen] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function deletePost() {
    if (deleting) return;
    setDeleting(true);
    setError(null);

    try {
      const res = await fetch(`/api/feed/posts/${postId}`, { method: "DELETE" });
      if (!res.ok) throw new Error("delete failed");

      setConfirmOpen(false);
      if (source === "detail") {
        router.replace(`/akun/postingan-saya?deleted=${copy.statusKey}`);
        router.refresh();
        return;
      }

      onDeleted?.(postId, copy);
    } catch {
      setError(friendlyDeleteError());
    } finally {
      setDeleting(false);
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setMenuOpen(true)}
        className={triggerClassName ?? "grid h-10 w-10 place-items-center rounded-full text-slate-900 transition active:bg-white"}
        aria-label="Buka aksi postingan"
      >
        <FiMoreVertical className="h-5 w-5" aria-hidden="true" />
      </button>

      <BottomSheet
        open={menuOpen}
        onClose={() => setMenuOpen(false)}
        title="Aksi postingan"
      >
        <div className="space-y-2">
          {source === "list" && (
            <Link
              href={detailHref}
              onClick={() => setMenuOpen(false)}
              className="flex w-full items-center justify-between rounded-2xl px-4 py-3 text-left text-sm font-black text-slate-900 transition active:bg-slate-50"
            >
              Lihat detail
              <FiChevronRight className="h-5 w-5 text-slate-300" aria-hidden="true" />
            </Link>
          )}
          <button
            type="button"
            onClick={() => {
              setMenuOpen(false);
              setConfirmOpen(true);
            }}
            className="flex w-full items-center gap-3 rounded-2xl px-4 py-3 text-left text-sm font-black text-red-600 transition active:bg-red-50"
          >
            <FiTrash2 className="h-5 w-5" aria-hidden="true" />
            {copy.actionLabel}
          </button>
          <button
            type="button"
            onClick={() => setMenuOpen(false)}
            className="flex w-full items-center gap-3 rounded-2xl px-4 py-3 text-left text-sm font-black text-slate-600 transition active:bg-slate-50"
          >
            <FiX className="h-5 w-5" aria-hidden="true" />
            Batal
          </button>
        </div>
      </BottomSheet>

      <BottomSheet
        open={confirmOpen}
        onClose={() => {
          if (!deleting) setConfirmOpen(false);
        }}
        title={copy.confirmTitle}
        footer={
          <div className="grid grid-cols-2 gap-3">
            <button
              type="button"
              disabled={deleting}
              onClick={() => setConfirmOpen(false)}
              className="rounded-2xl border border-slate-200 px-4 py-3 text-sm font-black text-slate-700 transition active:bg-slate-50 disabled:opacity-50"
            >
              Batal
            </button>
            <button
              type="button"
              disabled={deleting}
              onClick={deletePost}
              className="rounded-2xl bg-red-600 px-4 py-3 text-sm font-black text-white transition active:scale-[0.98] disabled:opacity-60"
            >
              {deleting ? "Menghapus..." : copy.confirmLabel}
            </button>
          </div>
        }
      >
        <div className="space-y-3">
          <p className="text-sm font-semibold leading-6 text-slate-600">
            {copy.confirmMessage}
          </p>
          {error && (
            <p className="rounded-2xl bg-red-50 px-4 py-3 text-sm font-bold leading-5 text-red-700">
              {error}
            </p>
          )}
        </div>
      </BottomSheet>
    </>
  );
}

function PostThumbnail({ src, duration }: { src: string | null; duration: string | null }) {
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
      {duration && (
        <span className="absolute bottom-2 left-2 rounded-md bg-black/70 px-2 py-0.5 text-[11px] font-black text-white">
          {duration}
        </span>
      )}
    </span>
  );
}

function DeletedEmptyState() {
  return (
    <section className="rounded-[24px] border border-slate-100 bg-white p-7 text-center shadow-[0_8px_24px_rgba(16,24,40,0.05)]">
      <span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-natalo-50 text-natalo-700">
        <FiPlayCircle className="h-7 w-7" aria-hidden="true" />
      </span>
      <h2 className="mt-4 text-base font-black text-slate-950">
        Belum ada postingan
      </h2>
      <p className="mt-1 text-sm font-semibold leading-5 text-slate-500">
        Yuk upload video pertamamu!
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
