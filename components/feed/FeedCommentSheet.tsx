"use client";

/**
 * Bottom sheet untuk komentar — spec 9: "Komentar ditampilkan dalam
 * bentuk bottom sheet agar user tidak pindah halaman".
 *
 * F3: read-only fetch. F4: tambah input + posting + like comment.
 * Spec 10.7: load 20 komentar pertama, lazy load berikutnya.
 */
import { useEffect, useState } from "react";
import { FiHeart, FiSend } from "react-icons/fi";
import { BottomSheet } from "@/components/BottomSheet";
import { hapticTap } from "@/lib/native/haptics";
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
  const [draft, setDraft] = useState("");
  const [posting, setPosting] = useState(false);
  const [postError, setPostError] = useState<string | null>(null);

  // Reset state saat ganti post / tutup
  useEffect(() => {
    if (!open || !postId) {
      setComments([]);
      setNextCursor(null);
      setError(null);
      setDraft("");
      setPostError(null);
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

  async function submitComment() {
    if (!postId) return;
    const content = draft.trim();
    if (!content || posting) return;
    setPosting(true);
    setPostError(null);
    try {
      const res = await fetch(`/api/feed/posts/${postId}/comments`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content }),
      });
      const data = await res.json();
      if (!res.ok) {
        if (res.status === 401) {
          setPostError("Login dulu untuk komentar.");
        } else {
          setPostError(data.error ?? "Gagal kirim komentar.");
        }
        return;
      }
      // Prepend new comment ke list
      setComments((prev) => [data.comment, ...prev]);
      setDraft("");
      hapticTap();
    } catch {
      setPostError("Tidak bisa terhubung. Coba lagi.");
    } finally {
      setPosting(false);
    }
  }

  const commentFooter = (
    <div className="flex items-end gap-2">
      <textarea
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        placeholder="Tulis komentar..."
        rows={1}
        maxLength={1000}
        className="flex-1 resize-none rounded-2xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm focus:border-natalo-500 focus:bg-white focus:outline-none"
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            submitComment();
          }
        }}
      />
      <button
        type="button"
        onClick={submitComment}
        disabled={!draft.trim() || posting}
        aria-label="Kirim komentar"
        className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-natalo-600 text-white transition active:scale-95 disabled:cursor-not-allowed disabled:bg-gray-300"
      >
        <FiSend className="h-4 w-4" />
      </button>
    </div>
  );

  return (
    <BottomSheet open={open} onClose={onClose} title="Komentar" footer={commentFooter}>
      <div className="space-y-3">
        {postError && (
          <p className="rounded-2xl bg-red-50 p-2.5 text-xs font-bold text-red-700">
            {postError}
          </p>
        )}
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
  const [liked, setLiked] = useState(comment.viewerLiked);
  const [likeCount, setLikeCount] = useState(comment.likeCount);
  const [busy, setBusy] = useState(false);

  async function toggleLike() {
    if (busy) return;
    setBusy(true);
    const prevLiked = liked;
    const prevCount = likeCount;
    setLiked(!prevLiked);
    setLikeCount(prevLiked ? Math.max(0, prevCount - 1) : prevCount + 1);
    hapticTap();
    try {
      const res = await fetch(`/api/feed/comments/${comment.id}/like`, { method: "POST" });
      if (!res.ok) throw new Error();
      const data: { liked: boolean; likeCount: number } = await res.json();
      setLiked(data.liked);
      setLikeCount(data.likeCount);
    } catch {
      setLiked(prevLiked);
      setLikeCount(prevCount);
    } finally {
      setBusy(false);
    }
  }

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
        <button
          type="button"
          onClick={toggleLike}
          aria-label={liked ? "Batal suka komentar" : "Suka komentar"}
          aria-pressed={liked}
          className="mt-1 flex items-center gap-1 text-[11px] font-bold text-gray-500 transition active:scale-95"
        >
          <FiHeart
            className={`h-3.5 w-3.5 ${liked ? "fill-red-500 stroke-red-500" : ""}`}
          />
          <span>{likeCount > 0 ? likeCount : ""}</span>
        </button>
      </div>
    </div>
  );
}
