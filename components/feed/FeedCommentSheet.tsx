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
import { createPortal } from "react-dom";
import Image from "next/image";
import Link from "next/link";
import { FiCheckCircle, FiHeart, FiSend, FiShoppingBag, FiSmile, FiX } from "react-icons/fi";
import { formatRupiah } from "@/lib/format";
import { hapticTap } from "@/lib/native/haptics";
import type {
  FeedCommentItem,
  FeedCommentsResponse,
  FeedPostListItem,
} from "@/lib/feed/types";

type Props = {
  open: boolean;
  postId: string | null;
  post?: FeedPostListItem | null;
  commentCount?: number | null;
  onClose: () => void;
};

type CommentSheetProduct =
  | NonNullable<FeedPostListItem["product"]>
  | FeedPostListItem["taggedProducts"][number];

const DRAG_CLOSE_THRESHOLD = 96;
const SNAP_BACK_MS = 280;
const SNAP_BACK_EASE = "cubic-bezier(0.34, 1.26, 0.64, 1)";
const KEYBOARD_INSET_THRESHOLD = 120;
const COMMENT_COMPOSER_HEIGHT = 76;
const COMMENT_REPLY_COMPOSER_HEIGHT = 118;

export function FeedCommentSheet({
  open,
  postId,
  post,
  commentCount,
  onClose,
}: Props) {
  const [comments, setComments] = useState<FeedCommentItem[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [draft, setDraft] = useState("");
  const [replyTo, setReplyTo] = useState<FeedCommentItem | null>(null);
  const [posting, setPosting] = useState(false);
  const [postError, setPostError] = useState<string | null>(null);
  const sheetRef = useRef<HTMLDivElement | null>(null);
  const composerRef = useRef<HTMLDivElement | null>(null);
  const inputRef = useRef<HTMLTextAreaElement | null>(null);
  const viewportBaselineRef = useRef(0);
  const dragStartYRef = useRef(0);
  const dragYRef = useRef(0);
  const isDraggingRef = useRef(false);
  const snapBackTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [dragY, setDragY] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [isSnappingBack, setIsSnappingBack] = useState(false);
  const [keyboardOpen, setKeyboardOpen] = useState(false);

  const visibleCommentTotal = useMemo(() => countThreadedComments(comments), [comments]);
  const creatorCaption = useMemo(() => getFeedPostCaption(post), [post]);
  const sheetProduct = useMemo(() => getFeedSheetProduct(post), [post]);

  const title = useMemo(() => {
    const total = Math.max(Number(commentCount ?? visibleCommentTotal) || 0, visibleCommentTotal);
    return total > 0 ? `Komentar ${formatCommentCount(total)}` : "Komentar";
  }, [commentCount, visibleCommentTotal]);

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
      setReplyTo(null);
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
      setReplyTo(null);
    }
  }, [open]);

  useEffect(() => {
    if (!open || typeof document === "undefined") return;
    const originalOverflow = document.body.style.overflow;
    document.body.classList.add("comments-open");
    document.body.style.overflow = "hidden";
    return () => {
      document.body.classList.remove("comments-open");
      document.body.style.overflow = originalOverflow;
    };
  }, [open]);

  useEffect(() => {
    if (!open || typeof window === "undefined") {
      setKeyboardOpen(false);
      viewportBaselineRef.current = 0;
      document.body.classList.remove("keyboard-open");
      document.documentElement.style.removeProperty("--kb");
      document.documentElement.style.removeProperty("--feed-comment-sheet-height");
      return;
    }

    const visualViewport = window.visualViewport;
    const root = document.documentElement;
    const body = document.body;
    let pluginKeyboardHeight = 0;
    let cancelled = false;

    function setKeyboardState(height: number, source: "plugin" | "viewport") {
      if (cancelled) return;
      const nextKeyboardOpen = height > KEYBOARD_INSET_THRESHOLD;
      const keyboardHeight = nextKeyboardOpen ? Math.round(height) : 0;

      setKeyboardOpen(nextKeyboardOpen);
      body.classList.toggle("keyboard-open", nextKeyboardOpen);
      root.style.setProperty("--kb", `${keyboardHeight}px`);
      root.style.setProperty(
        "--feed-comment-sheet-height",
        nextKeyboardOpen ? "42dvh" : "56dvh",
      );

      if (source === "plugin") {
        pluginKeyboardHeight = keyboardHeight;
      }
    }

    function updateKeyboardInset() {
      const visibleHeight = visualViewport?.height ?? window.innerHeight;
      const viewportOffsetTop = visualViewport?.offsetTop ?? 0;
      viewportBaselineRef.current = Math.max(
        viewportBaselineRef.current,
        window.innerHeight,
        visibleHeight,
      );
      const overlayInset = Math.max(
        0,
        window.innerHeight - visibleHeight - viewportOffsetTop,
      );
      const viewportLoss = Math.max(0, viewportBaselineRef.current - visibleHeight);
      const estimatedKeyboardHeight = Math.max(overlayInset, viewportLoss);
      if (pluginKeyboardHeight > 0 && estimatedKeyboardHeight < KEYBOARD_INSET_THRESHOLD) {
        return;
      }
      setKeyboardState(estimatedKeyboardHeight, "viewport");
    }

    updateKeyboardInset();
    visualViewport?.addEventListener("resize", updateKeyboardInset);
    visualViewport?.addEventListener("scroll", updateKeyboardInset);
    window.addEventListener("resize", updateKeyboardInset);

    let removeKeyboardListeners: (() => void) | null = null;
    void (async () => {
      try {
        const { Keyboard } = await import("@capacitor/keyboard");
        if (cancelled) return;
        const willShow = await Keyboard.addListener("keyboardWillShow", (info) => {
          setKeyboardState(info.keyboardHeight, "plugin");
        });
        const didShow = await Keyboard.addListener("keyboardDidShow", (info) => {
          setKeyboardState(info.keyboardHeight, "plugin");
        });
        const willHide = await Keyboard.addListener("keyboardWillHide", () => {
          setKeyboardState(0, "plugin");
        });
        const didHide = await Keyboard.addListener("keyboardDidHide", () => {
          setKeyboardState(0, "plugin");
        });
        removeKeyboardListeners = () => {
          void willShow.remove();
          void didShow.remove();
          void willHide.remove();
          void didHide.remove();
        };
      } catch {
        // Browser/PWA fallback tetap memakai visualViewport.
      }
    })();

    return () => {
      cancelled = true;
      visualViewport?.removeEventListener("resize", updateKeyboardInset);
      visualViewport?.removeEventListener("scroll", updateKeyboardInset);
      window.removeEventListener("resize", updateKeyboardInset);
      removeKeyboardListeners?.();
      body.classList.remove("keyboard-open");
      root.style.removeProperty("--kb");
      root.style.removeProperty("--feed-comment-sheet-height");
    };
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
        body: JSON.stringify({
          content,
          parentCommentId: replyTo?.id ?? undefined,
        }),
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
      if (data.comment.parentCommentId) {
        setComments((prev) =>
          prev.map((item) =>
            item.id === data.comment.parentCommentId
              ? {
                  ...item,
                  replies: [...(item.replies ?? []), data.comment],
                  replyCount: (item.replyCount ?? item.replies?.length ?? 0) + 1,
                }
              : item,
          ),
        );
      } else {
        // Prepend new top-level comment ke list
        setComments((prev) => [data.comment, ...prev]);
      }
      setDraft("");
      setReplyTo(null);
      hapticTap();
    } catch {
      setPostError("Tidak bisa terhubung. Coba lagi.");
    } finally {
      setPosting(false);
    }
  }

  function blurCommentInput() {
    const activeElement = document.activeElement;
    if (
      activeElement instanceof HTMLElement &&
      (sheetRef.current?.contains(activeElement) ||
        composerRef.current?.contains(activeElement))
    ) {
      activeElement.blur();
      return true;
    }
    return false;
  }

  function dismissKeyboardFromSheet(target: EventTarget | null) {
    if (!keyboardOpen) return;
    if (
      target instanceof HTMLElement &&
      target.closest("textarea, input, button, a")
    ) {
      return;
    }
    blurCommentInput();
  }

  function handleReply(comment: FeedCommentItem) {
    setReplyTo(comment);
    hapticTap();
    requestAnimationFrame(() => {
      inputRef.current?.focus();
    });
  }

  const replyAuthorName = replyTo ? getCommentAuthorName(replyTo) : null;
  const composerHeight = replyTo ? COMMENT_REPLY_COMPOSER_HEIGHT : COMMENT_COMPOSER_HEIGHT;

  const commentFooter = (
    <div className="w-full">
      {replyAuthorName && (
        <div className="mb-2 flex items-center justify-between gap-3 rounded-2xl border border-white/10 bg-white/[0.06] px-3 py-2 text-xs font-bold text-white/68">
          <span className="min-w-0 truncate">Membalas {replyAuthorName}</span>
          <button
            type="button"
            onPointerDown={(event) => event.stopPropagation()}
            onClick={(event) => {
              event.preventDefault();
              event.stopPropagation();
              setReplyTo(null);
            }}
            className="grid h-6 w-6 shrink-0 place-items-center rounded-full text-white/58 transition active:bg-white/10 active:text-white"
            aria-label="Batal balas"
          >
            <FiX className="h-4 w-4" />
          </button>
        </div>
      )}
      <div className="flex w-full items-end gap-2">
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
          ref={inputRef}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onFocus={() => {
            document.documentElement.style.setProperty(
              "--feed-comment-sheet-height",
              "42dvh",
            );
          }}
          onBlur={() => {
            window.setTimeout(() => {
              if (!document.body.classList.contains("keyboard-open")) {
                document.documentElement.style.setProperty(
                  "--feed-comment-sheet-height",
                  "56dvh",
                );
              }
            }, 80);
          }}
          placeholder={replyAuthorName ? `Balas ${replyAuthorName}...` : "Tulis komentar..."}
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
    </div>
  );

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <>
      <div
        data-no-pull
        data-no-swipe-back="true"
        className="fixed inset-0 z-[9000] bg-black/76 backdrop-blur-[1px]"
        onClick={() => {
          if (keyboardOpen && blurCommentInput()) return;
          onClose();
        }}
      />
      <section
        ref={sheetRef}
        data-no-pull
        data-no-swipe-back="true"
        role="dialog"
        aria-modal="false"
        aria-label={title}
        className="feed-comment-sheet fixed inset-x-0 z-[9010] mx-auto flex w-full max-w-2xl flex-col overflow-hidden rounded-t-[28px] border border-white/10 bg-[#111418]/[0.98] text-white shadow-[0_-28px_80px_rgba(0,0,0,0.5)] outline-none backdrop-blur-xl"
        style={{
          height: "var(--feed-comment-sheet-height, 56dvh)",
          bottom: `calc(${composerHeight}px + var(--kb, 0px))`,
          transform:
            isDragging || isSnappingBack
              ? `translate3d(0, ${dragY}px, 0)`
              : undefined,
          transition: isDragging
            ? "none"
            : isSnappingBack
              ? `transform ${SNAP_BACK_MS}ms ${SNAP_BACK_EASE}, height 220ms cubic-bezier(0.22, 1, 0.36, 1)`
              : "height 220ms cubic-bezier(0.22, 1, 0.36, 1)",
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
              <div className="feed-comment-handle h-1.5 w-10 rounded-full bg-white/24" />
            </div>
            <div className="feed-comment-header grid min-h-12 grid-cols-[40px_1fr_40px] items-center">
              <span aria-hidden />
              <h3 className="text-center text-base font-black tracking-normal text-white">
                {title}
              </h3>
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

          {sheetProduct && (
            <CommentProductPreview product={sheetProduct} onOpen={onClose} />
          )}

          <div
            className="feed-comment-list min-h-0 flex-1 overflow-y-auto border-t border-white/8 px-5 py-4 [-webkit-overflow-scrolling:touch]"
            style={{
              paddingBottom: "16px",
              scrollPaddingBottom: "16px",
            }}
            onPointerDown={(event) => dismissKeyboardFromSheet(event.target)}
          >
            <div className="space-y-4">
              {post && creatorCaption && (
                <CreatorCaptionSection post={post} caption={creatorCaption} />
              )}
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
                <p
                  className={`text-center text-xs font-bold text-white/45 ${
                    creatorCaption ? "py-5" : "py-8"
                  }`}
                >
                  Belum ada komentar. Jadi yang pertama!
                </p>
              )}
              {comments.map((c) => (
                <CommentRow key={c.id} comment={c} onReply={handleReply} />
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

      </section>
      <div
        ref={composerRef}
        data-no-pull
        data-no-swipe-back="true"
        className="feed-comment-composer pointer-events-auto fixed inset-x-0 z-[9020] mx-auto flex h-[76px] w-full max-w-2xl items-center border-t border-white/10 bg-[#111418] px-4 py-2.5 text-white shadow-[0_-16px_36px_rgba(0,0,0,0.35)]"
        onPointerDown={(event) => event.stopPropagation()}
        style={{
          bottom: 0,
          transform: "translate3d(0, calc(var(--kb, 0px) * -1), 0)",
          height: `${composerHeight}px`,
          transition: "transform 280ms cubic-bezier(0.22, 1, 0.36, 1)",
          willChange: "transform",
        }}
      >
        {commentFooter}
      </div>
    </>,
    document.body,
  );
}

function CreatorCaptionSection({
  post,
  caption,
}: {
  post: FeedPostListItem;
  caption: string;
}) {
  const [expanded, setExpanded] = useState(false);
  const authorName = getFeedPostAuthorName(post);
  const isOfficial = post.author.role === "ADMIN";
  const shouldClamp = caption.length > 120;

  return (
    <div className="flex gap-3 rounded-2xl border border-white/8 bg-white/[0.04] p-3">
      <div
        className={`grid h-11 w-11 shrink-0 place-items-center rounded-full text-sm font-black ring-1 ${
          isOfficial
            ? "bg-[#D6A84A]/18 text-[#E8C878] ring-[#D6A84A]/24"
            : "bg-white/10 text-white ring-white/10"
        }`}
      >
        {isOfficial ? "N" : getInitial(authorName)}
      </div>

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <p className="text-sm font-extrabold text-white">{authorName}</p>
          {isOfficial && (
            <span className="inline-flex items-center gap-1 rounded-full bg-natalo-500/16 px-2 py-0.5 text-[10px] font-black uppercase text-sky-100 ring-1 ring-natalo-300/20">
              <FiCheckCircle className="h-3 w-3" aria-hidden="true" />
              Official
            </span>
          )}
        </div>

        {/* Caption utama post ditampilkan sebagai konteks creator, bukan komentar palsu. */}
        <p
          className={`mt-1 whitespace-pre-line text-[15px] leading-snug text-white/88 ${
            expanded ? "" : "line-clamp-3"
          }`}
        >
          {caption}
        </p>

        {shouldClamp && (
          <button
            type="button"
            onClick={() => setExpanded((value) => !value)}
            className="mt-1 text-sm font-extrabold text-white/82 transition active:text-white"
          >
            {expanded ? "Sembunyikan" : "Selengkapnya"}
          </button>
        )}
      </div>
    </div>
  );
}

function CommentProductPreview({
  product,
  onOpen,
}: {
  product: CommentSheetProduct;
  onOpen: () => void;
}) {
  const displayPrice = getCommentSheetProductPrice(product);

  return (
    <Link
      href={`/products/${product.slug}`}
      onClick={onOpen}
      className="flex shrink-0 items-center gap-3 border-t border-white/8 bg-white/[0.035] px-5 py-3 text-left transition active:bg-white/[0.07]"
    >
      <div className="relative grid h-14 w-14 shrink-0 place-items-center overflow-hidden rounded-xl bg-white/8 text-white/55 ring-1 ring-white/10">
        {product.imageUrl ? (
          <Image
            src={product.imageUrl}
            alt={product.name}
            width={56}
            height={56}
            sizes="56px"
            className="h-full w-full object-cover"
          />
        ) : (
          <FiShoppingBag className="h-5 w-5" aria-hidden="true" />
        )}
      </div>

      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-extrabold text-white">
          {product.name}
        </p>
        {typeof displayPrice === "number" && (
          <p className="mt-0.5 text-sm font-black text-sky-200">
            {formatRupiah(displayPrice)}
          </p>
        )}
      </div>

      <span className="text-2xl font-light text-white/45" aria-hidden="true">
        ›
      </span>
    </Link>
  );
}

function CommentRow({
  comment,
  onReply,
  isReply = false,
  parentComment,
}: {
  comment: FeedCommentItem;
  onReply: (comment: FeedCommentItem) => void;
  isReply?: boolean;
  parentComment?: FeedCommentItem;
}) {
  const [liked, setLiked] = useState(comment.viewerLiked);
  const [likeCount, setLikeCount] = useState(comment.likeCount);
  const [busy, setBusy] = useState(false);
  const replyTarget = isReply && parentComment ? parentComment : comment;

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
    <div className="relative z-[3] [pointer-events:auto]">
      <div className={`flex gap-3 ${isReply ? "pl-12" : ""}`}>
        <div className={`${isReply ? "h-7 w-7 text-[10px]" : "h-9 w-9 text-xs"} flex shrink-0 items-center justify-center rounded-full bg-white/10 font-black text-white ring-1 ring-white/10`}>
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
          <p className={`${isReply ? "text-[13px]" : "text-sm"} mt-0.5 break-words leading-relaxed text-white/82`}>
            {comment.content}
          </p>
          <div className="relative z-[4] mt-1.5 flex items-center gap-4 [pointer-events:auto]">
            <button
              type="button"
              onPointerDown={(event) => event.stopPropagation()}
              onClick={(event) => {
                event.preventDefault();
                event.stopPropagation();
                onReply(replyTarget);
              }}
              className="-ml-2 rounded-full px-2 py-1.5 text-[11px] font-bold text-white/38 transition [pointer-events:auto] [touch-action:manipulation] active:text-white/70"
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
      {!isReply && comment.replies && comment.replies.length > 0 && (
        <div className="mt-3 space-y-3 border-l border-white/10 pl-1">
          {comment.replies.map((reply) => (
            <CommentRow
              key={reply.id}
              comment={reply}
              onReply={onReply}
              isReply
              parentComment={comment}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function countThreadedComments(items: FeedCommentItem[]) {
  return items.reduce(
    (total, item) => total + 1 + (item.replies?.length ?? 0),
    0,
  );
}

function getFeedPostCaption(post: FeedPostListItem | null | undefined) {
  if (!post) return "";
  const raw = (post.description?.trim() || post.title || "").trim();
  if (!raw) return "";

  return raw
    .split(/\n+/)
    .map((line) => line.trim())
    .filter((line) => line && !/^info peliharaan\s*:/i.test(line))
    .join("\n")
    .replace(/\s*info peliharaan\s*:\s*(cat|dog|other|kucing|anjing|lainnya)\s*$/i, "")
    .trim();
}

function getFeedPostAuthorName(post: FeedPostListItem) {
  return post.author.role === "ADMIN" ? "Natalo Petshop" : post.author.name;
}

function getFeedSheetProduct(post: FeedPostListItem | null | undefined): CommentSheetProduct | null {
  if (!post) return null;
  return post.taggedProducts[0] ?? post.product ?? null;
}

function getCommentSheetProductPrice(product: CommentSheetProduct) {
  if ("promoPrice" in product && typeof product.promoPrice === "number") {
    return product.promoPrice;
  }
  return product.discountPrice ?? product.price;
}

function getInitial(name: string) {
  return name.trim().charAt(0).toUpperCase() || "U";
}

function getCommentAuthorName(comment: FeedCommentItem) {
  return comment.author.role === "ADMIN" ? "Natalo Petshop" : comment.author.name;
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
