"use client";

/**
 * Bottom sheet untuk komentar — spec 9: "Komentar ditampilkan dalam
 * bentuk bottom sheet agar user tidak pindah halaman".
 *
 * F3: read-only fetch. F4: tambah input + posting + like comment.
 * Spec 10.7: load 20 komentar pertama, lazy load berikutnya.
 */
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type MouseEvent,
  type TouchEvent,
} from "react";
import { FiHeart, FiSend, FiSmile, FiX } from "react-icons/fi";
import { Drawer } from "vaul";
import { hapticTap } from "@/lib/native/haptics";
import type { FeedCommentItem, FeedCommentsResponse } from "@/lib/feed/types";

type Props = {
  open: boolean;
  postId: string | null;
  commentCount?: number | null;
  onClose: () => void;
};

const DRAG_CLOSE_THRESHOLD = 96;
const SNAP_BACK_MS = 280;
const SNAP_BACK_EASE = "cubic-bezier(0.34, 1.26, 0.64, 1)";

export function FeedCommentSheet({
  open,
  postId,
  commentCount,
  onClose,
}: Props) {
  const [comments, setComments] = useState<FeedCommentItem[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [draft, setDraft] = useState("");
  const [posting, setPosting] = useState(false);
  const [postError, setPostError] = useState<string | null>(null);
  const sheetRef = useRef<HTMLDivElement | null>(null);
  const dragStartYRef = useRef(0);
  const dragYRef = useRef(0);
  const isDraggingRef = useRef(false);
  const snapBackTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [dragY, setDragY] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [isSnappingBack, setIsSnappingBack] = useState(false);

  const title = useMemo(() => {
    const total = Math.max(Number(commentCount ?? comments.length) || 0, comments.length);
    return total > 0 ? `Komentar ${formatCommentCount(total)}` : "Komentar";
  }, [commentCount, comments.length]);

  const updateDrag = useCallback((clientY: number) => {
    if (!isDraggingRef.current) return;
    const nextDragY = Math.max(0, clientY - dragStartYRef.current);
    dragYRef.current = nextDragY;
    setDragY(nextDragY);
  }, []);

  const finishDrag = useCallback(() => {
    if (!isDraggingRef.current) return;
    isDraggingRef.current = false;
    setIsDragging(false);

    const sheetHeight = sheetRef.current?.getBoundingClientRect().height ?? 420;
    const closeThreshold = Math.min(DRAG_CLOSE_THRESHOLD, sheetHeight * 0.28);
    if (dragYRef.current >= closeThreshold) {
      onClose();
      return;
    }

    setIsSnappingBack(true);
    dragYRef.current = 0;
    setDragY(0);
    snapBackTimerRef.current = setTimeout(
      () => setIsSnappingBack(false),
      SNAP_BACK_MS,
    );
  }, [onClose]);

  const beginDrag = useCallback((target: EventTarget | null, clientY: number) => {
    if (target instanceof HTMLElement && target.closest("button, textarea, input")) {
      return;
    }
    if (snapBackTimerRef.current) clearTimeout(snapBackTimerRef.current);
    dragStartYRef.current = clientY;
    dragYRef.current = 0;
    isDraggingRef.current = true;
    setDragY(0);
    setIsDragging(true);
    setIsSnappingBack(false);
  }, []);

  const handleMouseDown = useCallback(
    (event: MouseEvent<HTMLDivElement>) => {
      if (event.button !== 0) return;
      beginDrag(event.target, event.clientY);
    },
    [beginDrag],
  );

  const handleTouchStart = useCallback(
    (event: TouchEvent<HTMLDivElement>) => {
      const touch = event.touches[0];
      if (!touch) return;
      beginDrag(event.target, touch.clientY);
    },
    [beginDrag],
  );

  const handleTouchMove = useCallback(
    (event: TouchEvent<HTMLDivElement>) => {
      const touch = event.touches[0];
      if (!touch) return;
      updateDrag(touch.clientY);
      if (dragYRef.current > 0 && event.cancelable) event.preventDefault();
    },
    [updateDrag],
  );

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

  useEffect(() => {
    if (!open) {
      setDragY(0);
      dragYRef.current = 0;
      isDraggingRef.current = false;
      setIsDragging(false);
      setIsSnappingBack(false);
    }
  }, [open]);

  useEffect(() => {
    if (!isDragging) return;

    function handleMouseMove(event: globalThis.MouseEvent) {
      updateDrag(event.clientY);
      if (dragYRef.current > 0) event.preventDefault();
    }

    function handleMouseUp() {
      finishDrag();
    }

    document.addEventListener("mousemove", handleMouseMove, { passive: false });
    document.addEventListener("mouseup", handleMouseUp);
    return () => {
      document.removeEventListener("mousemove", handleMouseMove);
      document.removeEventListener("mouseup", handleMouseUp);
    };
  }, [finishDrag, isDragging, updateDrag]);

  useEffect(() => {
    if (!open) return;
    function handler(event: KeyboardEvent) {
      if (event.key === "Escape") onClose();
    }
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [open, onClose]);

  useEffect(() => {
    return () => {
      if (snapBackTimerRef.current) clearTimeout(snapBackTimerRef.current);
    };
  }, []);

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
      <div className="mb-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/10 text-[11px] font-black text-white ring-1 ring-white/10">
        K
      </div>
      <button
        type="button"
        aria-label="Emoji"
        className="mb-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-full text-white/55 transition active:scale-95 active:bg-white/10"
      >
        <FiSmile className="h-5 w-5" />
      </button>
      <textarea
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        placeholder="Tulis komentar..."
        rows={1}
        maxLength={1000}
        className="max-h-28 min-h-10 flex-1 resize-none rounded-2xl border border-white/10 bg-white/[0.08] px-3 py-2.5 text-sm leading-5 text-white placeholder:text-white/42 focus:border-white/25 focus:bg-white/[0.12] focus:outline-none"
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
        className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-natalo-600 text-white shadow-lg shadow-natalo-950/30 transition active:scale-95 disabled:cursor-not-allowed disabled:bg-white/12 disabled:text-white/35 disabled:shadow-none"
      >
        <FiSend className="h-4 w-4" />
      </button>
    </div>
  );

  if (!open || typeof document === "undefined") return null;

  return (
    <Drawer.Root
      open={open}
      onOpenChange={(nextOpen) => {
        if (!nextOpen) onClose();
      }}
      direction="bottom"
      modal={false}
      dismissible={false}
      handleOnly
      noBodyStyles
    >
      <Drawer.Portal>
        <Drawer.Overlay
          data-no-pull
          data-no-swipe-back="true"
          className="fixed inset-0 z-[150] bg-black/76 backdrop-blur-[1px]"
          onClick={onClose}
        />
        <Drawer.Content
          ref={sheetRef}
          data-no-pull
          data-no-swipe-back="true"
          aria-describedby={undefined}
          className="fixed inset-x-0 bottom-0 z-[200] mx-auto flex w-full max-w-2xl flex-col overflow-hidden rounded-t-[28px] border border-white/10 bg-[#111418]/[0.98] text-white shadow-[0_-28px_80px_rgba(0,0,0,0.5)] outline-none backdrop-blur-xl"
          onOpenAutoFocus={(event) => event.preventDefault()}
          style={{
            top:
              "clamp(calc(env(safe-area-inset-top) + 286px), 42dvh, calc(env(safe-area-inset-top) + 374px))",
            transform:
              isDragging || isSnappingBack
                ? `translate3d(0, ${dragY}px, 0)`
                : undefined,
            transition: isDragging
              ? "none"
              : isSnappingBack
                ? `transform ${SNAP_BACK_MS}ms ${SNAP_BACK_EASE}`
                : undefined,
          }}
        >
          <div
            className="shrink-0 px-5 pb-3 pt-2"
            onMouseDown={handleMouseDown}
            onTouchStart={handleTouchStart}
            onTouchMove={handleTouchMove}
            onTouchEnd={finishDrag}
            onTouchCancel={finishDrag}
          >
            <div className="flex justify-center py-2">
              <div className="h-1.5 w-10 rounded-full bg-white/24" />
            </div>
            <div className="grid grid-cols-[40px_1fr_40px] items-center">
              <span aria-hidden />
              <Drawer.Title className="text-center text-base font-black tracking-normal text-white">
                {title}
              </Drawer.Title>
              <button
                type="button"
                aria-label="Tutup komentar"
                onClick={onClose}
                className="grid h-9 w-9 place-items-center rounded-full text-white/62 transition active:scale-95 active:bg-white/10 active:text-white"
              >
                <FiX className="h-5 w-5" />
              </button>
            </div>
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto border-t border-white/8 px-5 py-4 [-webkit-overflow-scrolling:touch]">
            <div className="space-y-4">
              {postError && (
                <p className="rounded-2xl bg-red-500/12 p-2.5 text-xs font-bold text-red-200 ring-1 ring-red-400/20">
                  {postError}
                </p>
              )}
              {loading && (
                <p className="py-8 text-center text-xs font-bold text-white/45">
                  Memuat komentar...
                </p>
              )}
              {error && (
                <p className="rounded-2xl bg-red-500/12 p-3 text-center text-xs font-bold text-red-200 ring-1 ring-red-400/20">
                  {error}
                </p>
              )}
              {!loading && !error && comments.length === 0 && (
                <p className="py-8 text-center text-xs font-bold text-white/45">
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
                  className="w-full rounded-full border border-white/10 py-2.5 text-xs font-extrabold text-white/75 transition active:bg-white/10 disabled:opacity-50"
                >
                  {loadingMore ? "Memuat..." : "Muat lebih banyak"}
                </button>
              )}
            </div>
          </div>

          <div className="sticky bottom-0 z-10 shrink-0 border-t border-white/10 bg-[#111418]/95 px-4 pt-3 [padding-bottom:calc(14px+env(safe-area-inset-bottom))]">
            {commentFooter}
          </div>
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
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
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-white/10 text-xs font-black text-white ring-1 ring-white/10">
        {comment.author.role === "ADMIN" ? "N" : comment.author.name.charAt(0).toUpperCase()}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <p className="min-w-0 truncate text-xs font-extrabold text-white">
            {comment.author.role === "ADMIN" ? "Natalo Petshop" : comment.author.name}
          </p>
          <span className="shrink-0 text-[11px] font-semibold text-white/38">
            {formatCommentTime(comment.createdAt)}
          </span>
          {comment.isAdminOfficial && (
            <span className="shrink-0 rounded-full bg-natalo-500/90 px-1.5 py-0.5 text-[9px] font-black uppercase text-white">
              Official
            </span>
          )}
        </div>
        <p className="mt-0.5 break-words text-sm leading-relaxed text-white/82">
          {comment.content}
        </p>
        <div className="mt-1.5 flex items-center gap-4">
          <button
            type="button"
            className="text-[11px] font-bold text-white/38 transition active:text-white/70"
          >
            Balas
          </button>
          <button
            type="button"
            onClick={toggleLike}
            aria-label={liked ? "Batal suka komentar" : "Suka komentar"}
            aria-pressed={liked}
            className="flex items-center gap-1 text-[11px] font-bold text-white/38 transition active:scale-95 active:text-white/70"
          >
            <FiHeart
              className={`h-3.5 w-3.5 ${liked ? "fill-red-500 stroke-red-500 text-red-500" : ""}`}
            />
            <span>{likeCount > 0 ? likeCount : ""}</span>
          </button>
        </div>
      </div>
    </div>
  );
}

function formatCommentCount(count: number) {
  if (count >= 1_000_000) {
    return `${(count / 1_000_000).toFixed(count >= 10_000_000 ? 0 : 1).replace(/\.0$/, "")}M`;
  }
  if (count >= 1_000) {
    return `${(count / 1_000).toFixed(count >= 10_000 ? 0 : 1).replace(/\.0$/, "")}K`;
  }
  return String(count);
}

function formatCommentTime(iso: string) {
  const created = new Date(iso).getTime();
  if (!Number.isFinite(created)) return "";
  const diffSeconds = Math.max(0, Math.floor((Date.now() - created) / 1000));
  if (diffSeconds < 60) return "baru";
  const diffMinutes = Math.floor(diffSeconds / 60);
  if (diffMinutes < 60) return `${diffMinutes}m`;
  const diffHours = Math.floor(diffMinutes / 60);
  if (diffHours < 24) return `${diffHours}j`;
  const diffDays = Math.floor(diffHours / 24);
  if (diffDays < 7) return `${diffDays}h`;
  return new Date(iso).toLocaleDateString("id-ID", {
    day: "numeric",
    month: "short",
  });
}
