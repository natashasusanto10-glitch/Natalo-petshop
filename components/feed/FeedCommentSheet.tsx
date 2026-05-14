"use client";

/**
 * Bottom sheet untuk komentar — spec 9: "Komentar ditampilkan dalam
 * bentuk bottom sheet agar user tidak pindah halaman".
 *
 * MVP read-only: fetch + render. Posting komentar di F4.
 * Spec 10.7: load 10-20 komentar pertama, lazy load berikutnya saat scroll.
 */
import { useEffect, useState } from "react";
import { BottomSheet } from "@/components/BottomSheet";
import type { FeedCommentItem, FeedCommentsResponse } from "@/lib/feed/types";

type Props = {
  open: boolean;
  postId: string | null;
  onClose: () => void;
};

export function FeedCommentSheet({ open, postId, onClose }: Props) {
  const [comments, setComments] = useState<FeedCommentItem[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);

  // Reset state saat ganti post / tutup
  useEffect(() => {
    if (!open || !postId) {
      setComments([]);
      setNextCursor(null);
      setError(null);
      return;
    }
    let cancelled = false;
    setLoading(true);
    fetch(`/api/feed/posts/${postId}/comments`)
      .then((r) => {
        if (!r.ok) throw new Error("Gagal memuat komentar");
        return r.json() as Promise<FeedCommentsResponse>;
      })
      .then((data) => {
        if (cancelled) return;
        setComments(data.items);
        setNextCursor(data.nextCursor);
        setError(null);
      })
      .catch((err) => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : "Gagal memuat");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [open, postId]);

  async function loadMore() {
    if (!postId || !nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const res = await fetch(`/api/feed/posts/${postId}/comments?cursor=${nextCursor}`);
      if (!res.ok) throw new Error("Gagal memuat lebih");
      const data: FeedCommentsResponse = await res.json();
      setComments((prev) => [...prev, ...data.items]);
      setNextCursor(data.nextCursor);
    } catch {
      // silent, retry tap lagi
    } finally {
      setLoadingMore(false);
    }
  }

  return (
    <BottomSheet open={open} onClose={onClose} title="Komentar">
      <div className="space-y-3">
        {loading && (
          <p className="py-8 text-center text-xs font-bold text-gray-400">Memuat komentar...</p>
        )}
        {error && (
          <p className="rounded-2xl bg-red-50 p-3 text-center text-xs font-bold text-red-600">
            {error}
          </p>
        )}
        {!loading && !error && comments.length === 0 && (
          <p className="py-8 text-center text-xs font-bold text-gray-400">
            Belum ada komentar. Jadi yang pertama!
          </p>
        )}
        {comments.map((c) => (
          <CommentRow key={c.id} comment={c} />
        ))}
        {nextCursor && (
          <button
            type="button"
            onClick={loadMore}
            disabled={loadingMore}
            className="w-full rounded-full border border-gray-200 py-2.5 text-xs font-extrabold text-gray-700 transition active:bg-gray-50 disabled:opacity-50"
          >
            {loadingMore ? "Memuat..." : "Muat lebih banyak"}
          </button>
        )}
      </div>
    </BottomSheet>
  );
}

function CommentRow({ comment }: { comment: FeedCommentItem }) {
  return (
    <div className="flex gap-3">
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-natalo-100 text-xs font-black text-natalo-700">
        {comment.author.role === "ADMIN" ? "N" : comment.author.name.charAt(0).toUpperCase()}
      </div>
      <div className="min-w-0 flex-1">
        <p className="flex items-center gap-1.5 text-xs font-extrabold text-gray-900">
          {comment.author.role === "ADMIN" ? "Natalo Petshop" : comment.author.name}
          {comment.isAdminOfficial && (
            <span className="rounded-full bg-natalo-600 px-1.5 py-0.5 text-[9px] font-black uppercase text-white">
              Official
            </span>
          )}
        </p>
        <p className="mt-0.5 break-words text-sm leading-relaxed text-gray-700">
          {comment.content}
        </p>
      </div>
    </div>
  );
}
