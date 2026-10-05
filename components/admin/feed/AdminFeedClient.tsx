"use client";

import { useAdminConfirm } from "@/components/admin/ui/useAdminConfirm";

/**
 * Admin Feed dashboard — list + filter + manage actions.
 *
 * Filter berbasis jenis konten (bukan status review — semua post auto-ACTIVE):
 *   Semua | Foto/Carousel | Video | Disembunyikan | Sampah
 *
 * Actions per row:
 *   - ACTIVE  : Hide / Delete
 *   - HIDDEN  : Unhide / Delete
 *   - Sampah  : Restore / Hapus permanen
 */
import Link from "next/link";
import Image from "next/image";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { FiPlus, FiRefreshCw } from "react-icons/fi";
import { Badge, Button, PageHeader } from "@/components/admin/ui";
import { useAdminToast } from "@/components/admin/ui";
import { AdminDialog } from "@/components/admin/ui/AdminDialog";
import { AdminFeedPreview, type FeedPreviewProduct } from "./AdminFeedPreview";
import {
  FiEye,
  FiHeart,
  FiMessageCircle,
  FiSearch,
  FiMoreHorizontal,
  FiPlay,
  FiShoppingBag,
} from "react-icons/fi";

type AdminFilter = "all" | "attention" | "hidden" | "deleted";

type AdminFeedItem = {
  id: string;
  canEdit?: boolean;
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
  taggedProducts?: FeedPreviewProduct[];
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
  counts: {
    total: number;
    deleted: number;
    photo: number;
    video: number;
    ready?: number;
    processing?: number;
    failed?: number;
  };
};

const FILTERS: { value: AdminFilter; label: string }[] = [
  { value: "all", label: "Semua" },
  { value: "attention", label: "Perlu perhatian" },
  { value: "hidden", label: "Disembunyikan" },
  { value: "deleted", label: "Sampah" },
];

export function AdminFeedClient() {
  const { confirm, confirmation } = useAdminConfirm();
  const { show } = useAdminToast();
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [format, setFormat] = useState("all");
  const [preview, setPreview] = useState<AdminFeedItem | null>(null);
  const [hidePost, setHidePost] = useState<string | null>(null);
  const [note, setNote] = useState("");
  useEffect(() => {
    const timer = setTimeout(() => setQuery(search.trim()), 300);
    return () => clearTimeout(timer);
  }, [search]);
  const [filter, setFilter] = useState<AdminFilter>("all");
  const [items, setItems] = useState<AdminFeedItem[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [counts, setCounts] = useState<AdminFeedResponse["counts"]>({
    total: 0,
    deleted: 0,
    photo: 0,
    video: 0,
  });
  const [actionBusy, setActionBusy] = useState<string | null>(null); // post id
  const [syncBusy, setSyncBusy] = useState(false);

  // Bulk selection — set of postId yang user centang. Action bar inline
  // muncul saat ≥1 row selected. Reset saat filter berubah (post mungkin
  // sudah tidak match filter baru).
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [bulkBusy, setBulkBusy] = useState(false);
  const isTrashView = filter === "deleted";
  const queryParameters = useMemo(
    () => new URLSearchParams({ filter, q: query, format }).toString(),
    [filter, query, format]
  );
  const parametersRef = useRef(queryParameters);
  const requestVersion = useRef(0);
  const managementBusy = Boolean(actionBusy || bulkBusy || syncBusy);

  // Refetch saat filter berubah. Inline fn supaya exhaustive-deps tidak
  // complain (kalau pakai useCallback yang depend ke `cursor`, akan trigger
  // re-fetch tiap kali cursor di-update — infinite loop).
  useEffect(() => {
    let cancelled = false;
    parametersRef.current = queryParameters;
    const version = ++requestVersion.current;
    setLoading(true);
    setCursor(null);
    setItems([]);
    setError(null);
    setSelectedIds(new Set()); // clear bulk selection saat filter ganti
    fetch(`/api/admin/feed/posts?${queryParameters}`)
      .then((r) => {
        if (!r.ok) throw new Error("Gagal memuat");
        return r.json() as Promise<AdminFeedResponse>;
      })
      .then((data) => {
        if (cancelled || version !== requestVersion.current) return;
        setItems(data.items);
        setCursor(data.nextCursor);
        setHasMore(Boolean(data.nextCursor));
        setCounts(data.counts);
      })
      .catch((err) => {
        if (cancelled || version !== requestVersion.current) return;
        setError(err instanceof Error ? err.message : "Gagal memuat");
      })
      .finally(() => {
        if (!cancelled && version === requestVersion.current) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [queryParameters]);

  // Load-more fetcher (terpisah supaya tidak invalidate-and-refetch saat filter sama).
  const loadMore = useCallback(async () => {
    if (!cursor || loadingMore) return;
    setLoadingMore(true);
    const version = requestVersion.current;
    try {
      const res = await fetch(
        `/api/admin/feed/posts?${queryParameters}&cursor=${encodeURIComponent(
          cursor
        )}`
      );
      if (!res.ok) throw new Error("Gagal memuat");
      const data: AdminFeedResponse = await res.json();
      if (version !== requestVersion.current) return;
      setItems((prev) => [...prev, ...data.items]);
      setCursor(data.nextCursor);
      setHasMore(Boolean(data.nextCursor));
    } catch (err) {
      if (version === requestVersion.current)
        setError(err instanceof Error ? err.message : "Gagal memuat");
    } finally {
      setLoadingMore(false);
    }
  }, [queryParameters, cursor, loadingMore]);

  // Refetch helper untuk dipakai setelah moderate action — pakai current filter.
  const refetchCurrent = useCallback(async () => {
    const version = ++requestVersion.current;
    const parameters = parametersRef.current;
    setLoading(true);
    try {
      const res = await fetch(`/api/admin/feed/posts?${parameters}`);
      if (!res.ok) throw new Error("Gagal memuat");
      const data: AdminFeedResponse = await res.json();
      if (version !== requestVersion.current) return;
      setSelectedIds(new Set());
      setItems(data.items);
      setCursor(data.nextCursor);
      setHasMore(Boolean(data.nextCursor));
      setCounts(data.counts);
      setError(null);
    } catch (err) {
      if (version === requestVersion.current)
        setError(err instanceof Error ? err.message : "Gagal memuat");
    } finally {
      if (version === requestVersion.current) setLoading(false);
    }
  }, []);

  async function moderate(
    postId: string,
    action: "hide" | "unhide" | "restore",
    suppliedNote?: string
  ) {
    if (action === "hide" && suppliedNote === undefined) {
      setNote("");
      setHidePost(postId);
      return;
    }
    const note = suppliedNote?.trim() || undefined;
    setActionBusy(postId);
    try {
      const res = await fetch(`/api/admin/feed/posts/${postId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, note }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gagal");
      setHidePost(null);
      show(
        action === "hide"
          ? "Postingan disembunyikan."
          : "Postingan ditampilkan kembali setelah media siap."
      );
      await refetchCurrent();
    } catch (err) {
      show(err instanceof Error ? err.message : "Gagal", "error");
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
    if (!(await confirm(confirmMsg))) return;
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
      show(
        isTrashView
          ? "Postingan dihapus permanen."
          : "Postingan dipindahkan ke sampah."
      );
      // Counts (esp. "deleted") akan stale setelah hard delete. Refetch
      // supaya badge "Sampah" up-to-date.
      await refetchCurrent();
    } catch (err) {
      show(err instanceof Error ? err.message : "Gagal", "error");
    } finally {
      setActionBusy(null);
    }
  }

  // Bulk action — kirim batch ke /api/admin/feed/posts/bulk. Per-item
  // result di-return supaya admin tahu ada yang skip (mis. status sudah
  // ACTIVE, tidak bisa di-approve lagi).
  async function bulkAction(
    action: "hide" | "unhide" | "restore" | "soft-delete" | "hard-delete"
  ) {
    if (bulkBusy || selectedIds.size === 0) return;

    const note: string | undefined = undefined;

    const labels: Record<typeof action, string> = {
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
    if (!(await confirm(confirmMsg))) return;

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
      const {
        applied,
        skipped,
        error: errs,
      } = data.summary ?? {
        applied: 0,
        skipped: 0,
        error: 0,
      };
      // Report per-item results without interrupting the workflow.
      const parts: string[] = [];
      parts.push(`${applied} berhasil`);
      if (skipped > 0) parts.push(`${skipped} dilewati`);
      if (errs > 0) parts.push(`${errs} gagal`);
      show(parts.join(" · "), "info");
      setSelectedIds(new Set());
      await refetchCurrent();
    } catch (err) {
      show(err instanceof Error ? err.message : "Bulk action gagal", "error");
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
      const ready =
        data.results?.filter((r) => r.action === "ready").length ?? 0;
      const failed =
        data.results?.filter((r) => r.action === "failed").length ?? 0;
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
      show(parts.join(" · "), "info");
      await refetchCurrent();
    } catch (err) {
      show(err instanceof Error ? err.message : "Sync gagal", "error");
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
    [items, selectedIds]
  );
  function toggleSelectAllVisible() {
    if (allVisibleSelected) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(items.map((p) => p.id)));
    }
  }

  return (
    <div className="af admin-feed-list">
      {confirmation}
      <PageHeader
        title="Feed"
        subtitle="Kelola cerita, produk, dan interaksi pelanggan."
        actions={
          <>
            <Button
              variant="secondary"
              onClick={syncBunny}
              disabled={managementBusy}
            >
              <FiRefreshCw
                aria-hidden
                className={syncBusy ? "animate-spin" : ""}
              />
              {syncBusy ? "Memeriksa…" : "Periksa video"}
            </Button>
            <Button href="/admin/feed/new">
              <FiPlus aria-hidden />
              Tambah postingan
            </Button>
          </>
        }
      />
      <div className="af-stats">
        {[
          ["Total postingan", counts.total],
          ["Postingan tayang", counts.ready],
          ["Dalam proses", counts.processing],
          ["Gagal diproses", counts.failed],
        ].map(([label, count]) => (
          <div key={label}>
            <span>{label}</span>
            <strong>
              {typeof count === "number" ? count.toLocaleString("id-ID") : "—"}
            </strong>
          </div>
        ))}
      </div>
      <section className="af-panel">
        <div className="af-toolbar">
          <label className="af-search">
            <FiSearch aria-hidden />
            <span className="sr-only">Cari judul, akun, atau produk</span>
            <input
              value={search}
              maxLength={120}
              onChange={(e) => {
                setSearch(e.target.value);
                setSelectedIds(new Set());
              }}
              placeholder="Cari judul, akun, atau produk…"
            />
          </label>
          <select
            aria-label="Format konten"
            value={format}
            onChange={(e) => setFormat(e.target.value)}
          >
            <option value="all">Semua format</option>
            <option value="video">Video</option>
            <option value="photo">Foto / Carousel</option>
            <option value="promo">Promo</option>
          </select>
        </div>
        <div className="af-tabs" aria-label="Status postingan">
          {FILTERS.map((f) => (
            <button
              key={f.value}
              type="button"
              aria-pressed={filter === f.value}
              onClick={() => setFilter(f.value)}
            >
              {f.label}
              {f.value === "deleted" && <span>{counts.deleted}</span>}
            </button>
          ))}
        </div>
        {error && (
          <div className="af-error" role="alert">
            <p>{error}</p>
            <Button variant="secondary" onClick={refetchCurrent}>
              Coba kembali
            </Button>
          </div>
        )}
        {loading ? (
          <div
            className="af-skeleton"
            role="status"
            aria-label="Memuat postingan"
          >
            {[1, 2, 3].map((n) => (
              <div key={n}>
                <span />
                <span />
              </div>
            ))}
          </div>
        ) : (
          <>
            {items.length > 0 && (
              <div className="af-table-head">
                <input
                  type="checkbox"
                  aria-label="Pilih semua postingan yang terlihat"
                  checked={allVisibleSelected}
                  onChange={toggleSelectAllVisible}
                  disabled={managementBusy}
                />
                <span>Postingan</span>
                <span>Status</span>
                <span>Interaksi</span>
                <span>Aksi</span>
              </div>
            )}
            {items.map((post) => (
              <AdminFeedRow
                key={post.id}
                post={post}
                busy={managementBusy}
                isTrashView={isTrashView}
                selected={selectedIds.has(post.id)}
                onToggleSelect={() => toggleSelected(post.id)}
                onModerate={(action) => void moderate(post.id, action)}
                onDelete={() => void deletePost(post.id)}
                onPreview={() => setPreview(post)}
              />
            ))}
            {!error && items.length === 0 && (
              <div className="af-empty">
                <FiSearch aria-hidden />
                <h2>Tidak ada postingan ditemukan</h2>
                <p>
                  {search
                    ? "Coba kata kunci lain atau ubah filter."
                    : "Belum ada postingan pada filter ini."}
                </p>
                <Button
                  variant="secondary"
                  onClick={() => {
                    setSearch("");
                    setFilter("all");
                    setFormat("all");
                  }}
                >
                  Reset filter
                </Button>
              </div>
            )}
            {items.length > 0 && (
              <div className="af-list-footer">
                {items.length} postingan dimuat
                <span>Terbaru terlebih dahulu</span>
              </div>
            )}
          </>
        )}
      </section>
      {hasMore && !loading && (
        <Button
          variant="secondary"
          onClick={() => void loadMore()}
          disabled={loadingMore || managementBusy}
        >
          {loadingMore ? "Memuat…" : "Muat lebih banyak"}
        </Button>
      )}
      {selectedIds.size > 0 && (
        <div className="af-bulk">
          <strong>{selectedIds.size} dipilih</strong>
          {(isTrashView
            ? [
                ["Pulihkan", "restore"],
                ["Hapus permanen", "hard-delete"],
              ]
            : [
                ["Sembunyikan", "hide"],
                ["Tampilkan", "unhide"],
                ["Ke sampah", "soft-delete"],
              ]
          ).map(([label, action]) => (
            <Button
              key={action}
              variant="secondary"
              disabled={managementBusy}
              onClick={() =>
                void bulkAction(action as Parameters<typeof bulkAction>[0])
              }
            >
              {label}
            </Button>
          ))}
          <Button
            variant="ghost"
            disabled={managementBusy}
            onClick={() => setSelectedIds(new Set())}
          >
            Batal
          </Button>
        </div>
      )}
      <AdminDialog
        open={Boolean(hidePost)}
        title="Sembunyikan postingan?"
        busy={Boolean(actionBusy)}
        onClose={() => setHidePost(null)}
        footer={
          <>
            <Button
              variant="secondary"
              disabled={Boolean(actionBusy)}
              onClick={() => setHidePost(null)}
            >
              Batal
            </Button>
            <Button
              disabled={Boolean(actionBusy)}
              onClick={() => hidePost && void moderate(hidePost, "hide", note)}
            >
              {actionBusy ? "Menyimpan…" : "Sembunyikan"}
            </Button>
          </>
        }
      >
        <p>Postingan tetap tersimpan dan dapat ditampilkan kembali.</p>
        <label className="af-note">
          Alasan (opsional)
          <textarea
            value={note}
            maxLength={500}
            onChange={(e) => setNote(e.target.value)}
            rows={3}
          />
        </label>
      </AdminDialog>
      <AdminDialog
        open={Boolean(preview)}
        title="Pratinjau Feed"
        onClose={() => setPreview(null)}
        className="af-preview-dialog"
      >
        {preview && (
          <AdminFeedPreview
            title={preview.title}
            description={preview.description}
            thumbnailUrl={preview.thumbnailUrl || preview.firstMediaUrl}
            videoUrl={preview.videoUrl}
            products={
              preview.taggedProducts?.length
                ? preview.taggedProducts
                : preview.product
                ? [preview.product]
                : []
            }
            author={
              preview.author.role === "ADMIN"
                ? "Natalo Petshop"
                : preview.author.name
            }
            official={preview.author.role === "ADMIN"}
            likeCount={preview.likeCount}
            commentCount={preview.commentCount}
          />
        )}
      </AdminDialog>
    </div>
  );
}

const KIND_LABEL: Record<string, string> = {
  VIDEO_PRODUCT: "Video produk",
  VIDEO_ONLY: "Video",
  USER_VIDEO: "Video",
  COMMUNITY: "Video",
  PHOTO_CAROUSEL: "Foto / Carousel",
  PRODUCT_ONLY: "Produk",
  PROMO: "Promo",
};
function AdminFeedRow({
  post,
  busy,
  isTrashView,
  selected,
  onToggleSelect,
  onModerate,
  onDelete,
  onPreview,
}: {
  post: AdminFeedItem;
  busy: boolean;
  isTrashView: boolean;
  selected: boolean;
  onToggleSelect(): void;
  onModerate(action: "hide" | "unhide" | "restore"): void;
  onDelete(): void;
  onPreview(): void;
}) {
  const thumb = post.thumbnailUrl || post.firstMediaUrl;
  const processing = ["uploading", "processing"].includes(post.encodingStatus);
  const status = isTrashView
    ? "Sampah"
    : post.status === "HIDDEN"
    ? "Disembunyikan"
    : post.status !== "ACTIVE"
    ? { PENDING_REVIEW: "Menunggu review", REJECTED: "Ditolak" }[post.status] ||
      post.status
    : post.encodingStatus === "failed"
    ? "Video gagal"
    : processing
    ? "Menunggu video"
    : "Tayang";
  const productCount = post.taggedProducts?.length || (post.product ? 1 : 0);
  return (
    <article className={`af-row ${selected ? "af-row-selected" : ""}`}>
      <input
        type="checkbox"
        checked={selected}
        onChange={onToggleSelect}
        disabled={busy}
        aria-label={`Pilih ${post.title}`}
      />
      <div className="af-row-content">
        <button
          className="af-thumb"
          type="button"
          aria-label={`Pratinjau ${post.title}`}
          onClick={onPreview}
        >
          {thumb ? (
            <Image
              src={thumb}
              fill
              sizes="64px"
              alt=""
              className="object-cover"
            />
          ) : (
            <FiShoppingBag aria-hidden />
          )}
          {post.kind !== "PHOTO_CAROUSEL" && thumb && (
            <FiPlay className="af-thumb-play" aria-hidden />
          )}
          {post.kind === "PHOTO_CAROUSEL" && post.mediaCount > 1 && (
            <span className="af-photo-count">{post.mediaCount}</span>
          )}
        </button>
        <div>
          <small>{KIND_LABEL[post.kind] || post.kind}</small>
          <h2>{post.title}</h2>
          <p>
            {post.author.name}
            <span>
              {" "}
              ·{" "}
              {new Date(post.createdAt).toLocaleDateString("id-ID", {
                day: "numeric",
                month: "short",
                year: "numeric",
              })}
            </span>
          </p>
          {productCount > 0 && (
            <div className="af-linked">
              <FiShoppingBag aria-hidden />
              {productCount} produk terkait
            </div>
          )}
          {post.moderationNote && (
            <p className="af-moderation-note">Catatan: {post.moderationNote}</p>
          )}
        </div>
      </div>
      <div className="af-row-status">
        <Badge
          variant={
            post.encodingStatus === "failed"
              ? "danger"
              : status === "Tayang"
              ? "success"
              : "neutral"
          }
        >
          {status}
        </Badge>
        <small>
          {processing
            ? "Video sedang diproses"
            : post.encodingStatus === "failed"
            ? "Periksa pemrosesan video"
            : "Media siap"}
        </small>
      </div>
      <div className="af-metrics">
        <strong>
          <FiEye aria-hidden />
          {post.viewCount.toLocaleString("id-ID")}
          <span className="sr-only">tayangan</span>
        </strong>
        <small>
          <FiHeart aria-hidden />
          {post.likeCount}
          <span className="sr-only">suka</span>
          <FiMessageCircle aria-hidden />
          {post.commentCount}
          <span className="sr-only">komentar</span>
        </small>
      </div>
      <div className="af-actions">
        {!isTrashView && (post.canEdit ?? post.author.role === "ADMIN") && (
          <Link href={`/admin/feed/${post.id}/edit`} className="af-edit">
            Edit<span className="sr-only"> {post.title}</span>
          </Link>
        )}
        <button
          type="button"
          aria-label={`Lihat ${post.title}`}
          onClick={onPreview}
        >
          <FiEye aria-hidden />
        </button>
        <details>
          <summary aria-label={`Aksi lainnya ${post.title}`}>
            <FiMoreHorizontal aria-hidden />
          </summary>
          <div>
            {!isTrashView && post.status === "ACTIVE" && (
              <button
                type="button"
                disabled={busy}
                onClick={() => onModerate("hide")}
              >
                Sembunyikan
              </button>
            )}
            {!isTrashView && post.status === "HIDDEN" && (
              <button
                type="button"
                disabled={busy}
                onClick={() => onModerate("unhide")}
              >
                Tampilkan kembali
              </button>
            )}
            {isTrashView && (
              <button
                type="button"
                disabled={busy}
                onClick={() => onModerate("restore")}
              >
                Pulihkan
              </button>
            )}
            <button
              type="button"
              className="af-danger"
              disabled={busy}
              onClick={onDelete}
            >
              {isTrashView ? "Hapus permanen" : "Pindah ke sampah"}
            </button>
            {post.videoUrl && (
              <a href={post.videoUrl} target="_blank" rel="noopener noreferrer">
                Buka video asli
              </a>
            )}
          </div>
        </details>
      </div>
    </article>
  );
}
