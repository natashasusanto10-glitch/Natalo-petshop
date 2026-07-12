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
  FiEdit2,
  FiExternalLink,
  FiPlus,
  FiRefreshCw,
  FiTrash2,
  FiX,
} from "react-icons/fi";
import { Badge, Button, PageHeader } from "@/components/admin/ui";
import type { BadgeVariant } from "@/components/admin/ui";

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

  // Bulk selection — set of postId yang user centang. Action bar inline
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
    <div className="space-y-4">
      <PageHeader
        title="Feed"
        subtitle={`${counts.total} post · ${counts.pending} menunggu review`}
        actions={
          <>
            <Button
              type="button"
              variant="secondary"
              size="sm"
              onClick={syncBunny}
              disabled={syncBusy}
              title="Polling Bunny untuk post yang nyangkut encoding (webhook miss)"
            >
              <FiRefreshCw className={`h-3.5 w-3.5 ${syncBusy ? "animate-spin" : ""}`} />
              {syncBusy ? "Sync…" : "Sync Bunny"}
            </Button>
            <Button href="/admin/feed/new" size="sm">
              <FiPlus className="h-4 w-4" />
              Buat post
            </Button>
          </>
        }
      />

      {/* Filter tabs */}
      <nav
        role="tablist"
        aria-label="Filter feed admin"
        className="-mx-1 flex gap-1.5 overflow-x-auto px-1 py-1"
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
              className={`flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-bold transition ${
                active
                  ? "border-natalo-600 bg-natalo-600 text-white"
                  : "border-zinc-200 bg-white text-zinc-600 hover:border-zinc-300 hover:bg-zinc-50"
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

      {loading && (
        <p className="py-12 text-center text-xs font-bold text-zinc-400">Memuat...</p>
      )}
      {error && (
        <p className="rounded-2xl bg-red-50 p-3 text-center text-sm font-bold text-red-700">
          {error}
        </p>
      )}
      {!loading && !error && items.length === 0 && (
        <p className="rounded-2xl border border-dashed border-zinc-200 bg-white p-8 text-center text-xs font-bold text-zinc-500">
          Tidak ada post di kategori ini.
        </p>
      )}

      {/* List — satu kartu dense berisi baris ber-border (bukan kartu
          bertumpuk terpisah), sejalan dengan halaman admin lain. */}
      {!loading && !error && items.length > 0 && (
        <div className="overflow-hidden rounded-2xl border border-zinc-200 bg-white">
          <div className="flex items-center gap-2 border-b border-zinc-100 bg-zinc-50 px-3 py-2">
            <input
              type="checkbox"
              checked={allVisibleSelected}
              onChange={toggleSelectAllVisible}
              disabled={bulkBusy}
              className="h-4 w-4 rounded border-zinc-300 text-natalo-600 focus:ring-natalo-400 disabled:opacity-50"
            />
            <span className="text-xs font-semibold text-zinc-600">
              {selectedIds.size > 0 ? `${selectedIds.size} dipilih` : "Pilih semua"}
            </span>
          </div>
          <div className="divide-y divide-zinc-100">
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
        </div>
      )}

      {hasMore && !loading && (
        <button
          type="button"
          onClick={() => loadMore()}
          disabled={loadingMore}
          className="w-full rounded-full border border-zinc-200 bg-white py-3 text-xs font-extrabold text-zinc-700 transition hover:bg-zinc-50 disabled:opacity-50"
        >
          {loadingMore ? "Memuat..." : "Muat lebih banyak"}
        </button>
      )}

      {/* Bulk action bar — inline di dalam alur konten (mengikuti lebar
          halaman), BUKAN lagi melayang full-width di bawah viewport. Actions
          tergantung view: trash view → Restore / Hapus Permanen. View lain
          → Approve/Reject, Hide, Pindah ke Sampah. */}
      {selectedIds.size > 0 && (
        <div className="sticky bottom-4 z-10 flex flex-wrap items-center gap-2 rounded-2xl border border-natalo-200 bg-white px-3 py-2.5 shadow-sm">
          <button
            type="button"
            onClick={() => setSelectedIds(new Set())}
            disabled={bulkBusy}
            aria-label="Batalkan seleksi"
            className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-zinc-100 text-zinc-600 transition hover:bg-zinc-200 disabled:opacity-50"
          >
            <FiX className="h-4 w-4" />
          </button>
          <span className="shrink-0 text-xs font-bold text-natalo-700">
            {selectedIds.size} dipilih
          </span>
          <div className="ml-auto flex flex-wrap gap-1.5">
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
      ? "bg-emerald-50 text-emerald-700 hover:bg-emerald-100"
      : tone === "red"
        ? "bg-red-50 text-red-700 hover:bg-red-100"
        : "bg-zinc-100 text-zinc-700 hover:bg-zinc-200";
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={busy}
      className={`shrink-0 rounded-full px-3 py-1.5 text-[11px] font-bold transition disabled:opacity-50 ${cls}`}
    >
      {label}
    </button>
  );
}

const KIND_LABEL: Record<string, string> = {
  VIDEO_PRODUCT: "Video produk",
  USER_VIDEO: "Video",
  VIDEO_ONLY: "Video",
  PHOTO_CAROUSEL: "Foto",
  COMMUNITY: "Diskusi",
  PRODUCT_ONLY: "Produk",
  PROMO: "Promo",
};

const STATUS_META: Record<string, { text: string; variant: BadgeVariant }> = {
  PENDING_REVIEW: { text: "Menunggu review", variant: "warning" },
  ACTIVE: { text: "Aktif", variant: "success" },
  REJECTED: { text: "Ditolak", variant: "danger" },
  HIDDEN: { text: "Disembunyikan", variant: "neutral" },
};

const ENCODING_META: Record<string, { text: string; variant: BadgeVariant }> = {
  uploading: { text: "Upload…", variant: "info" },
  processing: { text: "Encoding…", variant: "info" },
  failed: { text: "Encoding gagal", variant: "danger" },
};

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
  const statusMeta = STATUS_META[post.status] ?? {
    text: post.status,
    variant: "neutral" as BadgeVariant,
  };
  // Encoding badge — sembunyi kalau sudah "ready" (90% kasus). Yang penting
  // ditampilkan adalah state non-terminal/error supaya admin tahu kenapa
  // tombol Approve disabled atau kenapa post tidak muncul di feed.
  const encodingMeta = ENCODING_META[post.encodingStatus];
  const isApprovable = post.encodingStatus === "ready";

  const thumb = post.thumbnailUrl || post.firstMediaUrl;
  const isVideo =
    post.kind === "VIDEO_PRODUCT" ||
    post.kind === "USER_VIDEO" ||
    post.kind === "VIDEO_ONLY";
  const isPhoto = post.kind === "PHOTO_CAROUSEL";
  const kindLabel = KIND_LABEL[post.kind] ?? post.kind;

  return (
    <div
      className={`flex flex-col gap-3 px-3 py-3 transition md:flex-row md:items-center md:gap-4 ${
        selected ? "bg-natalo-50/60" : "hover:bg-zinc-50/60"
      }`}
    >
      <div className="flex min-w-0 flex-1 items-center gap-3">
        <input
          type="checkbox"
          checked={selected}
          onChange={onToggleSelect}
          disabled={busy}
          aria-label={selected ? "Batal pilih post" : "Pilih post"}
          className="h-4 w-4 shrink-0 rounded border-zinc-300 text-natalo-600 focus:ring-natalo-400 disabled:opacity-50"
        />

        {/* Thumbnail kecil — fallback chain:
            1. thumbnailUrl (video poster, Bunny generate)
            2. firstMediaUrl (PHOTO_CAROUSEL first image)
            3. Placeholder dengan icon kind */}
        <div className="relative h-14 w-11 shrink-0 overflow-hidden rounded-lg bg-zinc-100">
          {thumb ? (
            <>
              <Image src={thumb} alt="" fill sizes="44px" className="object-cover" />
              {/* Play icon overlay untuk video — visual cue thumbnail = video */}
              {isVideo && (
                <div className="absolute inset-0 grid place-items-center bg-black/20">
                  <div className="grid h-5 w-5 place-items-center rounded-full bg-white/90">
                    <svg className="h-2.5 w-2.5 text-zinc-900" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M8 5v14l11-7z" />
                    </svg>
                  </div>
                </div>
              )}
              {/* Counter badge untuk multi-photo */}
              {isPhoto && post.mediaCount > 1 && (
                <div className="absolute right-0.5 top-0.5 rounded-full bg-black/70 px-1 py-0.5 text-[8px] font-bold text-white">
                  {post.mediaCount}
                </div>
              )}
            </>
          ) : (
            <div className="grid h-full place-items-center text-[9px] font-bold text-zinc-300">
              No thumb
            </div>
          )}
        </div>

        {/* Info */}
        <div className="min-w-0 flex-1">
          <h3 className="truncate text-sm font-bold text-zinc-900">{post.title}</h3>
          <p className="mt-0.5 truncate text-[11px] text-zinc-500">
            {kindLabel} · {post.author.role === "ADMIN" ? "Admin" : "User"}{" "}
            {post.author.name} ·{" "}
            {new Date(post.createdAt).toLocaleDateString("id-ID", {
              day: "numeric",
              month: "short",
              year: "numeric",
            })}
          </p>
          <p className="mt-0.5 text-[11px] text-zinc-400">
            ♥ {post.likeCount} · 💬 {post.commentCount} · 👁 {post.viewCount}
          </p>
          {post.moderationNote && (
            <p className="mt-1 line-clamp-2 rounded-lg bg-zinc-50 px-2 py-1 text-[10px] italic text-zinc-500">
              Catatan: {post.moderationNote}
            </p>
          )}
        </div>
      </div>

      {/* Badges + actions — kolom kanan pada desktop, baris tersendiri di mobile. */}
      <div className="flex shrink-0 items-center gap-2 pl-7 md:pl-0">
        <div className="flex shrink-0 flex-col items-start gap-1 md:items-end">
          <Badge variant={statusMeta.variant}>{statusMeta.text}</Badge>
          {encodingMeta && <Badge variant={encodingMeta.variant}>{encodingMeta.text}</Badge>}
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
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
              aria-label="Edit"
              title="Edit"
              className="grid h-7 w-7 place-items-center rounded-full bg-blue-50 text-blue-700 transition hover:bg-blue-100"
            >
              <FiEdit2 className="h-3.5 w-3.5" />
            </Link>
          )}
          <button
            type="button"
            onClick={onDelete}
            disabled={busy}
            aria-label={isTrashView ? "Hapus permanen" : "Hapus"}
            title={isTrashView ? "Hapus permanen" : "Hapus"}
            className="grid h-7 w-7 place-items-center rounded-full bg-red-50 text-red-700 transition hover:bg-red-100 disabled:opacity-50"
          >
            <FiTrash2 className="h-3.5 w-3.5" />
          </button>
          {post.videoUrl && (
            <a
              href={post.videoUrl}
              target="_blank"
              rel="noopener noreferrer"
              aria-label="Buka video"
              title="Buka video"
              className="grid h-7 w-7 place-items-center rounded-full bg-zinc-100 text-zinc-600 transition hover:bg-zinc-200"
            >
              <FiExternalLink className="h-3.5 w-3.5" />
            </a>
          )}
        </div>
      </div>
    </div>
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
    green: "bg-emerald-600 text-white hover:bg-emerald-700",
    red: "bg-red-600 text-white hover:bg-red-700",
    gray: "bg-zinc-200 text-zinc-700 hover:bg-zinc-300",
  }[tone];
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={busy || disabled}
      title={title}
      className={`rounded-full px-2.5 py-1.5 text-[11px] font-bold transition disabled:cursor-not-allowed disabled:opacity-50 ${cls}`}
    >
      {label}
    </button>
  );
}
