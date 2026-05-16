"use client";

/**
 * Admin Feed dashboard — list + filter + moderation actions.
 *
 * Spec section 11 filter:
 *   Semua | Video Admin | Video User | Menunggu Review | Ditolak | Disembunyikan
 *
 * Actions per row:
 *   - PENDING_REVIEW: Approve / Reject (with note prompt)
 *   - ACTIVE       : Hide / Delete
 *   - HIDDEN       : Unhide / Delete
 *   - REJECTED     : Delete only
 */
import Link from "next/link";
import Image from "next/image";
import { useCallback, useEffect, useState } from "react";
import { FiEdit2, FiExternalLink, FiPlus, FiTrash2 } from "react-icons/fi";

type AdminFilter =
  | "all"
  | "admin_video"
  | "user_video"
  | "pending"
  | "rejected"
  | "hidden"
  | "deleted";

type AdminFeedItem = {
  id: string;
  status: string;
  kind: string;
  tab: string;
  title: string;
  description: string | null;
  videoUrl: string | null;
  thumbnailUrl: string | null;
  videoDurationSec: number | null;
  product: { id: string; slug: string; name: string } | null;
  promo: {
    originalPrice: number;
    discountPrice: number;
    startsAt: string | null;
    endsAt: string | null;
  } | null;
  likeCount: number;
  commentCount: number;
  viewCount: number;
  author: { id: string; name: string; role: string };
  moderatedBy: { id: string; name: string } | null;
  moderatedAt: string | null;
  moderationNote: string | null;
  publishedAt: string | null;
  createdAt: string;
};

type AdminFeedResponse = {
  items: AdminFeedItem[];
  nextCursor: string | null;
  counts: { pending: number; total: number; deleted: number };
};

const FILTERS: { value: AdminFilter; label: string }[] = [
  { value: "all", label: "Semua" },
  { value: "admin_video", label: "Video Admin" },
  { value: "user_video", label: "Video User" },
  { value: "pending", label: "Menunggu Review" },
  { value: "rejected", label: "Ditolak" },
  { value: "hidden", label: "Disembunyikan" },
  { value: "deleted", label: "Sampah" },
];

export function AdminFeedClient() {
  const [filter, setFilter] = useState<AdminFilter>("all");
  const [items, setItems] = useState<AdminFeedItem[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [counts, setCounts] = useState({ pending: 0, total: 0, deleted: 0 });
  const [actionBusy, setActionBusy] = useState<string | null>(null); // post id

  // Refetch saat filter berubah. Inline fn supaya exhaustive-deps tidak
  // complain (kalau pakai useCallback yang depend ke `cursor`, akan trigger
  // re-fetch tiap kali cursor di-update — infinite loop).
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setCursor(null);
    setItems([]);
    setError(null);
    fetch(`/api/admin/feed/posts?filter=${filter}`)
      .then((r) => {
        if (!r.ok) throw new Error("Gagal memuat");
        return r.json() as Promise<AdminFeedResponse>;
      })
      .then((data) => {
        if (cancelled) return;
        setItems(data.items);
        setCursor(data.nextCursor);
        setHasMore(Boolean(data.nextCursor));
        setCounts(data.counts);
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
  }, [filter]);

  // Load-more fetcher (terpisah supaya tidak invalidate-and-refetch saat filter sama).
  const loadMore = useCallback(async () => {
    if (!cursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const res = await fetch(`/api/admin/feed/posts?filter=${filter}&cursor=${cursor}`);
      if (!res.ok) throw new Error("Gagal memuat");
      const data: AdminFeedResponse = await res.json();
      setItems((prev) => [...prev, ...data.items]);
      setCursor(data.nextCursor);
      setHasMore(Boolean(data.nextCursor));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memuat");
    } finally {
      setLoadingMore(false);
    }
  }, [filter, cursor, loadingMore]);

  // Refetch helper untuk dipakai setelah moderate action — pakai current filter.
  const refetchCurrent = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch(`/api/admin/feed/posts?filter=${filter}`);
      if (!res.ok) throw new Error("Gagal memuat");
      const data: AdminFeedResponse = await res.json();
      setItems(data.items);
      setCursor(data.nextCursor);
      setHasMore(Boolean(data.nextCursor));
      setCounts(data.counts);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memuat");
    } finally {
      setLoading(false);
    }
  }, [filter]);

  async function moderate(
    postId: string,
    action: "approve" | "reject" | "hide" | "unhide",
  ) {
    let note: string | undefined;
    if (action === "reject") {
      const input = window.prompt("Alasan menolak video (wajib):");
      if (!input || !input.trim()) return;
      note = input.trim();
    } else if (action === "hide") {
      const input = window.prompt("Alasan menyembunyikan (opsional):");
      note = input?.trim() || undefined;
    }
    setActionBusy(postId);
    try {
      const res = await fetch(`/api/admin/feed/posts/${postId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, note }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gagal");
      // Refetch list supaya counts & status sync
      refetchCurrent();
    } catch (err) {
      window.alert(err instanceof Error ? err.message : "Gagal");
    } finally {
      setActionBusy(null);
    }
  }

  async function deletePost(postId: string) {
    if (!window.confirm("Hapus post ini permanent? Tidak bisa di-undo.")) return;
    setActionBusy(postId);
    try {
      const res = await fetch(`/api/admin/feed/posts/${postId}`, {
        method: "DELETE",
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? "Gagal hapus");
      }
      setItems((prev) => prev.filter((p) => p.id !== postId));
    } catch (err) {
      window.alert(err instanceof Error ? err.message : "Gagal");
    } finally {
      setActionBusy(null);
    }
  }

  return (
    <div className="mx-auto max-w-4xl">
      {/* Header */}
      <header className="mb-4 flex items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-black text-gray-900">Feed</h1>
          <p className="text-xs font-semibold text-gray-500">
            Total {counts.total} post · {counts.pending} menunggu review
          </p>
        </div>
        <Link
          href="/admin/feed/new"
          className="inline-flex items-center gap-1.5 rounded-full bg-natalo-600 px-4 py-2 text-xs font-extrabold text-white shadow-sm transition active:scale-95"
        >
          <FiPlus className="h-4 w-4" />
          Buat Post
        </Link>
      </header>

      {/* Filter tabs */}
      <nav
        role="tablist"
        aria-label="Filter feed admin"
        className="-mx-1 mb-4 flex gap-1.5 overflow-x-auto px-1 py-1"
      >
        {FILTERS.map((f) => {
          const active = filter === f.value;
          const badge =
            f.value === "pending" && counts.pending > 0 ? counts.pending : null;
          return (
            <button
              key={f.value}
              type="button"
              role="tab"
              aria-selected={active}
              onClick={() => setFilter(f.value)}
              className={`flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-extrabold transition ${
                active
                  ? "border-natalo-600 bg-natalo-600 text-white"
                  : "border-gray-200 bg-white text-gray-700 active:bg-gray-100"
              }`}
            >
              {f.label}
              {badge != null && (
                <span
                  className={`grid h-4 min-w-4 place-items-center rounded-full px-1 text-[10px] font-black ${
                    active ? "bg-white text-natalo-700" : "bg-amber-500 text-white"
                  }`}
                >
                  {badge}
                </span>
              )}
            </button>
          );
        })}
      </nav>

      {/* List */}
      {loading && (
        <p className="py-12 text-center text-xs font-bold text-gray-400">Memuat...</p>
      )}
      {error && (
        <p className="rounded-2xl bg-red-50 p-3 text-center text-sm font-bold text-red-700">
          {error}
        </p>
      )}
      {!loading && !error && items.length === 0 && (
        <p className="rounded-3xl border border-dashed border-gray-200 bg-white p-8 text-center text-xs font-bold text-gray-500">
          Tidak ada post di kategori ini.
        </p>
      )}

      <div className="space-y-3">
        {items.map((p) => (
          <AdminFeedRow
            key={p.id}
            post={p}
            busy={actionBusy === p.id}
            onModerate={(action) => moderate(p.id, action)}
            onDelete={() => deletePost(p.id)}
          />
        ))}
      </div>

      {hasMore && !loading && (
        <button
          type="button"
          onClick={() => loadMore()}
          disabled={loadingMore}
          className="mt-4 w-full rounded-full border border-gray-200 bg-white py-3 text-xs font-extrabold text-gray-700 transition active:bg-gray-50 disabled:opacity-50"
        >
          {loadingMore ? "Memuat..." : "Muat lebih banyak"}
        </button>
      )}
    </div>
  );
}

function AdminFeedRow({
  post,
  busy,
  onModerate,
  onDelete,
}: {
  post: AdminFeedItem;
  busy: boolean;
  onModerate: (action: "approve" | "reject" | "hide" | "unhide") => void;
  onDelete: () => void;
}) {
  const statusLabel: Record<string, { text: string; cls: string }> = {
    PENDING_REVIEW: {
      text: "Menunggu Review",
      cls: "bg-amber-100 text-amber-800",
    },
    ACTIVE: { text: "Aktif", cls: "bg-green-100 text-green-800" },
    REJECTED: { text: "Ditolak", cls: "bg-red-100 text-red-800" },
    HIDDEN: { text: "Disembunyikan", cls: "bg-gray-200 text-gray-700" },
  };
  const meta = statusLabel[post.status] ?? {
    text: post.status,
    cls: "bg-gray-100 text-gray-700",
  };

  return (
    <article className="overflow-hidden rounded-2xl border border-gray-100 bg-white">
      <div className="flex gap-3 p-3">
        {/* Thumbnail kecil */}
        <div className="relative h-24 w-16 shrink-0 overflow-hidden rounded-xl bg-gray-100">
          {post.thumbnailUrl ? (
            <Image
              src={post.thumbnailUrl}
              alt=""
              fill
              sizes="64px"
              className="object-cover"
            />
          ) : (
            <div className="grid h-full place-items-center text-[10px] font-bold text-gray-300">
              No thumb
            </div>
          )}
        </div>

        {/* Info */}
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <h3 className="line-clamp-2 text-sm font-extrabold text-gray-900">
              {post.title}
            </h3>
            <span
              className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-black uppercase ${meta.cls}`}
            >
              {meta.text}
            </span>
          </div>
          <p className="mt-1 truncate text-[11px] font-semibold text-gray-500">
            {post.kind} · {post.author.role === "ADMIN" ? "Admin" : "User"} {post.author.name} ·{" "}
            {new Date(post.createdAt).toLocaleDateString("id-ID", {
              day: "numeric",
              month: "short",
              year: "numeric",
            })}
          </p>
          <p className="mt-0.5 text-[11px] font-bold text-gray-500">
            ♥ {post.likeCount} · 💬 {post.commentCount} · 👁 {post.viewCount}
          </p>
          {post.moderationNote && (
            <p className="mt-1 line-clamp-2 rounded-lg bg-gray-50 px-2 py-1 text-[10px] italic text-gray-600">
              Catatan: {post.moderationNote}
            </p>
          )}
        </div>
      </div>

      {/* Actions */}
      <div className="flex flex-wrap items-center gap-1.5 border-t border-gray-100 bg-gray-50 px-3 py-2">
        {post.status === "PENDING_REVIEW" && (
          <>
            <ActionButton
              label="Setujui"
              tone="green"
              onClick={() => onModerate("approve")}
              busy={busy}
            />
            <ActionButton
              label="Tolak"
              tone="red"
              onClick={() => onModerate("reject")}
              busy={busy}
            />
          </>
        )}
        {post.status === "ACTIVE" && (
          <ActionButton
            label="Sembunyikan"
            tone="gray"
            onClick={() => onModerate("hide")}
            busy={busy}
          />
        )}
        {post.status === "HIDDEN" && (
          <ActionButton
            label="Tampilkan"
            tone="green"
            onClick={() => onModerate("unhide")}
            busy={busy}
          />
        )}
        {post.author.role === "ADMIN" && (
          <Link
            href={`/admin/feed/${post.id}/edit`}
            className="inline-flex items-center gap-1 rounded-full bg-blue-50 px-3 py-1.5 text-[11px] font-extrabold text-blue-700 transition active:bg-blue-100"
          >
            <FiEdit2 className="h-3 w-3" /> Edit
          </Link>
        )}
        <button
          type="button"
          onClick={onDelete}
          disabled={busy}
          className="inline-flex items-center gap-1 rounded-full bg-red-50 px-3 py-1.5 text-[11px] font-extrabold text-red-700 transition active:bg-red-100 disabled:opacity-50"
        >
          <FiTrash2 className="h-3 w-3" /> Hapus
        </button>
        {post.videoUrl && (
          <a
            href={post.videoUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="ml-auto inline-flex items-center gap-1 rounded-full bg-white px-3 py-1.5 text-[11px] font-extrabold text-gray-700 transition active:bg-gray-100"
          >
            <FiExternalLink className="h-3 w-3" /> Buka video
          </a>
        )}
      </div>
    </article>
  );
}

function ActionButton({
  label,
  tone,
  onClick,
  busy,
}: {
  label: string;
  tone: "green" | "red" | "gray";
  onClick: () => void;
  busy: boolean;
}) {
  const cls = {
    green: "bg-green-600 text-white active:bg-green-700",
    red: "bg-red-600 text-white active:bg-red-700",
    gray: "bg-gray-200 text-gray-700 active:bg-gray-300",
  }[tone];
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={busy}
      className={`rounded-full px-3 py-1.5 text-[11px] font-extrabold transition disabled:opacity-50 ${cls}`}
    >
      {label}
    </button>
  );
}
