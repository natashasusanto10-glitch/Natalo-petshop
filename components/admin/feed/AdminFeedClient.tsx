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
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  FiCheckSquare,
  FiEdit2,
  FiExternalLink,
  FiPlus,
  FiRefreshCw,
  FiSquare,
  FiTrash2,
  FiX,
} from "react-icons/fi";

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
  // Bunny encoding lifecycle. Approve di-block selama ini ≠ "ready" —
  // listFeedPosts filter encodingStatus="ready" untuk public feed, jadi
  // approve pre-ready bikin post "approved tapi invisible".
  encodingStatus: string;
  kind: string;
  tab: string;
  title: string;
  description: string | null;
  videoUrl: string | null;
  thumbnailUrl: string | null;
  /** First media URL untuk PHOTO_CAROUSEL — fallback thumbnail. */
  firstMediaUrl: string | null;
  /** Total media count — display "Foto (N)" badge. */
  mediaCount: number;
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
  const [syncBusy, setSyncBusy] = useState(false);

  // Bulk selection — set of postId yang user centang. Floating action bar
  // muncul saat ≥1 row selected. Reset saat filter berubah (post mungkin
  // sudah tidak match filter baru).
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [bulkBusy, setBulkBusy] = useState(false);
  const isTrashView = filter === "deleted";

  // Refetch saat filter berubah. Inline fn supaya exhaustive-deps tidak
  // complain (kalau pakai useCallback yang depend ke `cursor`, akan trigger
  // re-fetch tiap kali cursor di-update — infinite loop).
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setCursor(null);
    setItems([]);
    setError(null);
    setSelectedIds(new Set()); // clear bulk selection saat filter ganti
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
    action: "approve" | "reject" | "hide" | "unhide" | "restore",
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
    // Dari trash view (filter=deleted), post sudah soft-deleted. DELETE
    // tanpa ?hard=1 akan no-op (endpoint early-return alreadyDeleted=true),
    // jadi row "hilang" dari UI tapi nongol lagi saat refetch berikutnya.
    // Pakai hard=1 supaya row permanently dibuang + cascade FK + Bunny
    // cleanup. Dari filter lain (all/pending/dst), soft-delete (default)
    // supaya admin masih punya undo via tab Sampah → Restore.
    const confirmMsg = isTrashView
      ? "Hapus permanen dari sampah? Tidak bisa di-undo (post + komentar + likes ikut hilang)."
      : "Pindahkan post ini ke Sampah? Bisa di-restore dari tab Sampah.";
    if (!window.confirm(confirmMsg)) return;
    setActionBusy(postId);
    try {
      const url = isTrashView
        ? `/api/admin/feed/posts/${postId}?hard=1`
        : `/api/admin/feed/posts/${postId}`;
      const res = await fetch(url, { method: "DELETE" });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? "Gagal hapus");
      }
      setItems((prev) => prev.filter((p) => p.id !== postId));
      // Counts (esp. "deleted") akan stale setelah hard delete. Refetch
      // supaya badge "Sampah" up-to-date.
      refetchCurrent();
    } catch (err) {
      window.alert(err instanceof Error ? err.message : "Gagal");
    } finally {
      setActionBusy(null);
    }
  }

  // Bulk action — kirim batch ke /api/admin/feed/posts/bulk. Per-item
  // result di-return supaya admin tahu ada yang skip (mis. status sudah
  // ACTIVE, tidak bisa di-approve lagi).
  async function bulkAction(
    action:
      | "approve"
      | "reject"
      | "hide"
      | "unhide"
      | "restore"
      | "soft-delete"
      | "hard-delete",
  ) {
    if (bulkBusy || selectedIds.size === 0) return;

    let note: string | undefined;
    if (action === "reject") {
      const input = window.prompt(
        `Alasan menolak ${selectedIds.size} video (wajib):`,
      );
      if (!input || !input.trim()) return;
      note = input.trim();
    }

    const labels: Record<typeof action, string> = {
      approve: "Setujui",
      reject: "Tolak",
      hide: "Sembunyikan",
      unhide: "Tampilkan",
      restore: "Restore",
      "soft-delete": "Pindah ke Sampah",
      "hard-delete": "Hapus Permanen",
    };
    const isDestructive = action === "hard-delete";
    const confirmMsg = isDestructive
      ? `Hapus PERMANEN ${selectedIds.size} post? Tidak bisa di-undo.`
      : `${labels[action]} ${selectedIds.size} post?`;
    if (!window.confirm(confirmMsg)) return;

    setBulkBusy(true);
    try {
      const res = await fetch("/api/admin/feed/posts/bulk", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action,
          postIds: Array.from(selectedIds),
          note,
        }),
      });
      const data = (await res.json()) as {
        ok?: boolean;
        error?: string;
        summary?: { applied: number; skipped: number; error: number };
      };
      if (!res.ok || !data.ok) {
        throw new Error(data.error ?? "Bulk action gagal");
      }
      const { applied, skipped, error: errs } = data.summary ?? {
        applied: 0,
        skipped: 0,
        error: 0,
      };
      // Show summary toast-ish via alert (bisa diganti toast UI nanti).
      const parts: string[] = [];
      parts.push(`${applied} berhasil`);
      if (skipped > 0) parts.push(`${skipped} dilewati`);
      if (errs > 0) parts.push(`${errs} gagal`);
      window.alert(parts.join(" · "));
      setSelectedIds(new Set());
      refetchCurrent();
    } catch (err) {
      window.alert(err instanceof Error ? err.message : "Bulk action gagal");
    } finally {
      setBulkBusy(false);
    }
  }

  // Manual Bunny reconcile — polling Bunny untuk semua post yang masih
  // "uploading" / "processing". Dipakai admin kalau ada post nyangkut karena
  // webhook miss. Auto-reconcile di GET handler juga jalan, tapi tombol ini
  // bikin user-flow eksplisit + ngasih feedback summary.
  async function syncBunny() {
    if (syncBusy) return;
    setSyncBusy(true);
    try {
      const res = await fetch("/api/admin/feed/bunny-reconcile", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });
      const data = (await res.json()) as {
        ok?: boolean;
        scanned?: number;
        results?: Array<{ action: string }>;
        error?: string;
      };
      if (!res.ok || !data.ok) {
        throw new Error(data.error ?? "Sync gagal");
      }
      const ready = data.results?.filter((r) => r.action === "ready").length ?? 0;
      const failed = data.results?.filter((r) => r.action === "failed").length ?? 0;
      const skipped =
        data.results?.filter((r) => r.action === "skipped").length ?? 0;
      const scanned = data.scanned ?? 0;
      const parts: string[] = [];
      if (scanned === 0) parts.push("Tidak ada post yang stuck.");
      else {
        parts.push(`Scan ${scanned} post.`);
        if (ready > 0) parts.push(`${ready} siap tayang`);
        if (failed > 0) parts.push(`${failed} gagal encoding`);
        if (skipped > 0) parts.push(`${skipped} masih diproses`);
      }
      window.alert(parts.join(" · "));
      refetchCurrent();
    } catch (err) {
      window.alert(err instanceof Error ? err.message : "Sync gagal");
    } finally {
      setSyncBusy(false);
    }
  }

  function toggleSelected(postId: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(postId)) next.delete(postId);
      else next.add(postId);
      return next;
    });
  }

  // Select all visible (yang lagi di-render di list). Tidak include yang
  // belum di-load (cursor pagination).
  const allVisibleSelected = useMemo(
    () => items.length > 0 && items.every((p) => selectedIds.has(p.id)),
    [items, selectedIds],
  );
  function toggleSelectAllVisible() {
    if (allVisibleSelected) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(items.map((p) => p.id)));
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
        <div className="flex shrink-0 items-center gap-2">
          <button
            type="button"
            onClick={syncBunny}
            disabled={syncBusy}
            title="Polling Bunny untuk post yang nyangkut encoding (webhook miss)"
            className="inline-flex items-center gap-1.5 rounded-full border border-gray-200 bg-white px-3 py-2 text-[11px] font-extrabold text-gray-700 shadow-sm transition active:bg-gray-50 disabled:opacity-50"
          >
            <FiRefreshCw className={`h-3.5 w-3.5 ${syncBusy ? "animate-spin" : ""}`} />
            {syncBusy ? "Sync…" : "Sync Bunny"}
          </button>
          <Link
            href="/admin/feed/new"
            className="inline-flex items-center gap-1.5 rounded-full bg-natalo-600 px-4 py-2 text-xs font-extrabold text-white shadow-sm transition active:scale-95"
          >
            <FiPlus className="h-4 w-4" />
            Buat Post
          </Link>
        </div>
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

      {/* Select-all toolbar — muncul saat ada item di list. Tap untuk
          select semua visible (yg sudah di-load), tap lagi untuk clear. */}
      {!loading && items.length > 0 && (
        <div className="mb-2 flex items-center justify-between gap-2 rounded-xl bg-white px-3 py-2 text-xs font-bold text-gray-600 shadow-sm">
          <button
            type="button"
            onClick={toggleSelectAllVisible}
            disabled={bulkBusy}
            className="inline-flex items-center gap-1.5 transition active:scale-95 disabled:opacity-50"
          >
            {allVisibleSelected ? (
              <FiCheckSquare className="h-4 w-4 text-natalo-600" />
            ) : (
              <FiSquare className="h-4 w-4 text-gray-400" />
            )}
            <span>
              {allVisibleSelected
                ? `${items.length} terpilih`
                : "Pilih semua"}
            </span>
          </button>
          {selectedIds.size > 0 && (
            <span className="text-natalo-600">{selectedIds.size} dipilih</span>
          )}
        </div>
      )}

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

      <div className={`space-y-3 ${selectedIds.size > 0 ? "pb-24" : ""}`}>
        {items.map((p) => (
          <AdminFeedRow
            key={p.id}
            post={p}
            busy={actionBusy === p.id}
            isTrashView={isTrashView}
            selected={selectedIds.has(p.id)}
            onToggleSelect={() => toggleSelected(p.id)}
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

      {/* Floating bulk action bar — sticky di bawah viewport saat ada
          selection. Actions tergantung view: trash view → Restore /
          Hapus Permanen. View lain → Approve/Reject (untuk PENDING-heavy),
          Hide, Pindah ke Sampah. Admin pilih action yang relevan. */}
      {selectedIds.size > 0 && (
        <div className="fixed inset-x-0 bottom-0 z-50 border-t border-gray-200 bg-white shadow-[0_-4px_20px_rgba(0,0,0,0.08)]">
          <div className="mx-auto flex max-w-4xl items-center gap-2 overflow-x-auto px-3 py-3">
            <button
              type="button"
              onClick={() => setSelectedIds(new Set())}
              disabled={bulkBusy}
              aria-label="Batalkan seleksi"
              className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-gray-100 text-gray-600 transition active:bg-gray-200 disabled:opacity-50"
            >
              <FiX className="h-4 w-4" />
            </button>
            <span className="shrink-0 text-[11px] font-extrabold text-gray-700">
              {selectedIds.size} dipilih
            </span>
            <div className="ml-1 flex gap-1.5">
              {isTrashView ? (
                <>
                  <BulkBtn
                    label="Restore"
                    tone="green"
                    onClick={() => bulkAction("restore")}
                    busy={bulkBusy}
                  />
                  <BulkBtn
                    label="Hapus Permanen"
                    tone="red"
                    onClick={() => bulkAction("hard-delete")}
                    busy={bulkBusy}
                  />
                </>
              ) : (
                <>
                  <BulkBtn
                    label="Setujui"
                    tone="green"
                    onClick={() => bulkAction("approve")}
                    busy={bulkBusy}
                  />
                  <BulkBtn
                    label="Tolak"
                    tone="red"
                    onClick={() => bulkAction("reject")}
                    busy={bulkBusy}
                  />
                  <BulkBtn
                    label="Sembunyikan"
                    tone="gray"
                    onClick={() => bulkAction("hide")}
                    busy={bulkBusy}
                  />
                  <BulkBtn
                    label="Tampilkan"
                    tone="gray"
                    onClick={() => bulkAction("unhide")}
                    busy={bulkBusy}
                  />
                  <BulkBtn
                    label="Ke Sampah"
                    tone="red"
                    onClick={() => bulkAction("soft-delete")}
                    busy={bulkBusy}
                  />
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function BulkBtn({
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
  const cls =
    tone === "green"
      ? "bg-green-100 text-green-800 active:bg-green-200"
      : tone === "red"
        ? "bg-red-100 text-red-800 active:bg-red-200"
        : "bg-gray-100 text-gray-700 active:bg-gray-200";
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={busy}
      className={`shrink-0 rounded-full px-3 py-1.5 text-[11px] font-extrabold transition disabled:opacity-50 ${cls}`}
    >
      {label}
    </button>
  );
}

function AdminFeedRow({
  post,
  busy,
  isTrashView,
  selected,
  onToggleSelect,
  onModerate,
  onDelete,
}: {
  post: AdminFeedItem;
  busy: boolean;
  isTrashView: boolean;
  selected: boolean;
  onToggleSelect: () => void;
  onModerate: (
    action: "approve" | "reject" | "hide" | "unhide" | "restore",
  ) => void;
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

  // Encoding badge — sembunyi kalau sudah "ready" (90% kasus). Yang penting
  // ditampilkan adalah state non-terminal/error supaya admin tahu kenapa
  // tombol Approve disabled atau kenapa post tidak muncul di feed.
  const encodingMeta: Record<string, { text: string; cls: string }> = {
    uploading: { text: "Upload…", cls: "bg-sky-100 text-sky-800" },
    processing: { text: "Encoding…", cls: "bg-sky-100 text-sky-800" },
    failed: { text: "Encoding gagal", cls: "bg-red-100 text-red-800" },
  };
  const encoding = encodingMeta[post.encodingStatus];
  const isApprovable = post.encodingStatus === "ready";

  return (
    <article
      className={`overflow-hidden rounded-2xl border bg-white transition ${
        selected
          ? "border-natalo-500 ring-2 ring-natalo-200"
          : "border-gray-100"
      }`}
    >
      <div className="flex gap-3 p-3">
        {/* Bulk select checkbox — tap area besar (40x40) supaya mudah
            di-tap di mobile. Tap di mana saja di area thumbnail-side
            juga toggle selection (label wrap implicit via onClick). */}
        <button
          type="button"
          onClick={onToggleSelect}
          disabled={busy}
          aria-label={selected ? "Batal pilih post" : "Pilih post"}
          aria-pressed={selected}
          className="grid h-10 w-10 shrink-0 place-items-center self-center rounded-full text-gray-400 transition active:bg-gray-100 disabled:opacity-50"
        >
          {selected ? (
            <FiCheckSquare className="h-5 w-5 text-natalo-600" />
          ) : (
            <FiSquare className="h-5 w-5" />
          )}
        </button>

        {/* Thumbnail kecil — fallback chain:
            1. thumbnailUrl (video poster, Bunny generate)
            2. firstMediaUrl (PHOTO_CAROUSEL first image)
            3. Placeholder dengan icon kind */}
        {(() => {
          const thumb = post.thumbnailUrl || post.firstMediaUrl;
          const isVideo = post.kind === "VIDEO_PRODUCT" ||
            post.kind === "USER_VIDEO" ||
            post.kind === "VIDEO_ONLY";
          const isPhoto = post.kind === "PHOTO_CAROUSEL";
          const ringClass = isVideo
            ? "ring-2 ring-blue-200"
            : isPhoto
              ? "ring-2 ring-emerald-200"
              : "ring-1 ring-gray-200";
          return (
            <div
              className={`relative h-24 w-16 shrink-0 overflow-hidden rounded-xl bg-gray-100 ${ringClass}`}
            >
              {thumb ? (
                <>
                  <Image
                    src={thumb}
                    alt=""
                    fill
                    sizes="64px"
                    className="object-cover"
                  />
                  {/* Play icon overlay untuk video — visual cue thumbnail = video */}
                  {isVideo && (
                    <div className="absolute inset-0 grid place-items-center bg-black/20">
                      <div className="grid h-7 w-7 place-items-center rounded-full bg-white/90">
                        <svg
                          className="h-3.5 w-3.5 text-gray-900"
                          fill="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path d="M8 5v14l11-7z" />
                        </svg>
                      </div>
                    </div>
                  )}
                  {/* Counter badge untuk multi-photo */}
                  {isPhoto && post.mediaCount > 1 && (
                    <div className="absolute right-1 top-1 rounded-full bg-black/70 px-1.5 py-0.5 text-[9px] font-bold text-white">
                      {post.mediaCount}
                    </div>
                  )}
                </>
              ) : (
                <div className="grid h-full place-items-center text-gray-300">
                  {isPhoto ? (
                    <svg className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
                      <rect x="3" y="3" width="18" height="18" rx="2" />
                      <circle cx="8.5" cy="8.5" r="1.5" />
                      <path d="m21 15-5-5L5 21" />
                    </svg>
                  ) : isVideo ? (
                    <svg className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
                      <rect x="3" y="6" width="14" height="12" rx="2" />
                      <path d="m17 10 4-2v8l-4-2" />
                    </svg>
                  ) : (
                    <span className="text-[10px] font-bold">No thumb</span>
                  )}
                </div>
              )}
            </div>
          );
        })()}

        {/* Info */}
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <h3 className="line-clamp-2 text-sm font-extrabold text-gray-900">
              {post.title}
            </h3>
            <div className="flex shrink-0 flex-col items-end gap-1">
              <span
                className={`rounded-full px-2 py-0.5 text-[10px] font-black uppercase ${meta.cls}`}
              >
                {meta.text}
              </span>
              {encoding && (
                <span
                  className={`rounded-full px-2 py-0.5 text-[10px] font-black uppercase ${encoding.cls}`}
                >
                  {encoding.text}
                </span>
              )}
            </div>
          </div>
          {/* Kind badge dengan icon + Indonesian label */}
          <div className="mt-1 flex items-center gap-1.5 text-[11px] font-semibold text-gray-500">
            <span className="inline-flex items-center gap-1 rounded bg-gray-100 px-1.5 py-0.5 font-bold text-gray-700">
              {(() => {
                switch (post.kind) {
                  case "VIDEO_PRODUCT":
                    return <>🎥 Video Produk</>;
                  case "USER_VIDEO":
                  case "VIDEO_ONLY":
                    return <>🎥 Video</>;
                  case "PHOTO_CAROUSEL":
                    return (
                      <>
                        📷 Foto
                        {post.mediaCount > 1 && ` (${post.mediaCount})`}
                      </>
                    );
                  case "COMMUNITY":
                    return <>💬 Diskusi</>;
                  case "PRODUCT_ONLY":
                    return <>🏷️ Produk</>;
                  case "PROMO":
                    return <>🎁 Promo</>;
                  default:
                    return <>{post.kind}</>;
                }
              })()}
            </span>
            <span>·</span>
            <span className="truncate">
              {post.author.role === "ADMIN" ? "Admin" : "User"} {post.author.name}
            </span>
            <span>·</span>
            <span className="shrink-0">
              {new Date(post.createdAt).toLocaleDateString("id-ID", {
                day: "numeric",
                month: "short",
                year: "numeric",
              })}
            </span>
          </div>
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
        {/* Di trash view, post sudah soft-deleted. Sembunyikan dulu semua
            moderation buttons (Approve/Reject/Hide/Unhide) yang tidak make
            sense untuk row yang di sampah — tampilkan tombol Restore saja
            untuk lift soft-delete + Hapus untuk purge permanen. */}
        {!isTrashView && post.status === "PENDING_REVIEW" && (
          <>
            <ActionButton
              label="Setujui"
              tone="green"
              onClick={() => onModerate("approve")}
              busy={busy}
              disabled={!isApprovable}
              title={
                isApprovable
                  ? undefined
                  : post.encodingStatus === "failed"
                    ? "Video gagal di-encode — tolak / hapus saja"
                    : "Tunggu sampai encoding selesai"
              }
            />
            <ActionButton
              label="Tolak"
              tone="red"
              onClick={() => onModerate("reject")}
              busy={busy}
            />
          </>
        )}
        {!isTrashView && post.status === "ACTIVE" && (
          <ActionButton
            label="Sembunyikan"
            tone="gray"
            onClick={() => onModerate("hide")}
            busy={busy}
          />
        )}
        {!isTrashView && post.status === "HIDDEN" && (
          <ActionButton
            label="Tampilkan"
            tone="green"
            onClick={() => onModerate("unhide")}
            busy={busy}
          />
        )}
        {isTrashView && (
          <ActionButton
            label="Restore"
            tone="green"
            onClick={() => onModerate("restore")}
            busy={busy}
          />
        )}
        {!isTrashView && post.author.role === "ADMIN" && (
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
          <FiTrash2 className="h-3 w-3" /> {isTrashView ? "Hapus Permanen" : "Hapus"}
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
  disabled,
  title,
}: {
  label: string;
  tone: "green" | "red" | "gray";
  onClick: () => void;
  busy: boolean;
  disabled?: boolean;
  title?: string;
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
      disabled={busy || disabled}
      title={title}
      className={`rounded-full px-3 py-1.5 text-[11px] font-extrabold transition disabled:cursor-not-allowed disabled:opacity-50 ${cls}`}
    >
      {label}
    </button>
  );
}
