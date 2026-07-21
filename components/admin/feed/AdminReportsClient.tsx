"use client";

/**
 * Moderasi Laporan — antrean report UGC (post/komentar feed) dari user.
 *
 * Kenapa dipisah dari AdminFeedClient: report adalah antrean sendiri
 * (siapa lapor apa, kapan, alasan apa) yang butuh keputusan cepat —
 * beda cara pakai dari list-semua-post yang sudah ada di /admin/feed.
 * Endpoint hide/dismiss di sini reuse endpoint moderation post/comment
 * yang sudah ada (bukan endpoint baru).
 *
 * Filter tab: Menunggu (default) | Selesai | Diabaikan | Semua.
 * "Selesai" & "Diabaikan" read-only (riwayat) — actions cuma tampil di
 * tab Menunggu.
 */
import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { FiExternalLink } from "react-icons/fi";
import { Badge, Button, EmptyState, PageHeader } from "@/components/admin/ui";
import type { BadgeVariant } from "@/components/admin/ui";

type ReportStatus = "PENDING" | "RESOLVED" | "DISMISSED";
type ReportReason = "SPAM" | "INAPPROPRIATE" | "MISLEADING" | "COPYRIGHT" | "OTHER";

type ReportItem = {
  id: string;
  reason: ReportReason;
  detail: string | null;
  status: ReportStatus;
  createdAt: string;
  resolvedAt: string | null;
  reporter: { id: string; name: string; profilePhotoUrl: string | null } | null;
  post: {
    id: string;
    title: string;
    description: string | null;
    thumbnailUrl: string | null;
    kind: string;
    status: string;
    deletedAt: string | null;
    author: { id: string; name: string };
  } | null;
  comment: {
    id: string;
    content: string;
    isHidden: boolean;
    postId: string;
    author: { id: string; name: string };
  } | null;
};

type ReportsResponse = {
  reports: ReportItem[];
  nextCursor: string | null;
  counts: { pending: number; resolved: number; dismissed: number };
  filter: string;
};

type TabValue = "pending" | "resolved" | "dismissed" | "all";
const TABS: { value: TabValue; label: string }[] = [
  { value: "pending", label: "Menunggu" },
  { value: "resolved", label: "Selesai" },
  { value: "dismissed", label: "Diabaikan" },
  { value: "all", label: "Semua" },
];

const REASON_META: Record<ReportReason, { text: string; variant: BadgeVariant }> = {
  SPAM: { text: "Spam", variant: "neutral" },
  INAPPROPRIATE: { text: "Tidak pantas", variant: "danger" },
  MISLEADING: { text: "Menyesatkan", variant: "warning" },
  COPYRIGHT: { text: "Hak cipta", variant: "purple" },
  OTHER: { text: "Lainnya", variant: "neutral" },
};

/** Pisahkan "flutter_reason: xxx" + "note: yyy" dari field detail mentah. */
function parseDetail(detail: string | null): { subReason: string | null; note: string | null } {
  if (!detail) return { subReason: null, note: null };
  const lines = detail.split("\n");
  let subReason: string | null = null;
  let note: string | null = null;
  for (const line of lines) {
    if (line.startsWith("flutter_reason:")) subReason = line.replace("flutter_reason:", "").trim();
    if (line.startsWith("note:")) note = line.replace("note:", "").trim();
  }
  return { subReason, note };
}

function timeAgo(iso: string): string {
  const diffMs = Date.now() - new Date(iso).getTime();
  const min = Math.floor(diffMs / 60_000);
  if (min < 1) return "Baru saja";
  if (min < 60) return `${min} menit lalu`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr} jam lalu`;
  const day = Math.floor(hr / 24);
  if (day < 30) return `${day} hari lalu`;
  return new Date(iso).toLocaleDateString("id-ID", { day: "numeric", month: "short", year: "numeric" });
}

export function AdminReportsClient() {
  const [tab, setTab] = useState<TabValue>("pending");
  const [items, setItems] = useState<ReportItem[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [counts, setCounts] = useState({ pending: 0, resolved: 0, dismissed: 0 });
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async (status: TabValue, nextCursor?: string) => {
    const params = new URLSearchParams({ status });
    if (nextCursor) params.set("cursor", nextCursor);
    const res = await fetch(`/api/admin/feed/reports?${params.toString()}`);
    if (!res.ok) throw new Error("Gagal memuat laporan.");
    return (await res.json()) as ReportsResponse;
  }, []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    load(tab)
      .then((data) => {
        if (cancelled) return;
        setItems(data.reports);
        setCursor(data.nextCursor);
        setHasMore(Boolean(data.nextCursor));
        setCounts(data.counts);
      })
      .catch((err) => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : "Gagal memuat laporan.");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [tab, load]);

  const loadMore = useCallback(async () => {
    if (!cursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const data = await load(tab, cursor);
      setItems((prev) => [...prev, ...data.reports]);
      setCursor(data.nextCursor);
      setHasMore(Boolean(data.nextCursor));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memuat laporan.");
    } finally {
      setLoadingMore(false);
    }
  }, [cursor, loadingMore, tab, load]);

  const refetch = useCallback(async () => {
    try {
      const data = await load(tab);
      setItems(data.reports);
      setCursor(data.nextCursor);
      setHasMore(Boolean(data.nextCursor));
      setCounts(data.counts);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal memuat laporan.");
    }
  }, [tab, load]);

  async function setReportStatus(reportId: string, action: "resolve" | "dismiss") {
    const res = await fetch(`/api/admin/feed/reports/${reportId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error ?? "Gagal memperbarui laporan.");
  }

  async function hideAndResolve(report: ReportItem) {
    setBusyId(report.id);
    try {
      if (report.post) {
        const res = await fetch(`/api/admin/feed/posts/${report.post.id}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "hide", note: "Disembunyikan dari laporan user" }),
        });
        if (!res.ok) {
          const data = await res.json().catch(() => ({}));
          // Kalau post sudah HIDDEN/tidak ACTIVE, tetap lanjut resolve report —
          // tujuan akhirnya (konten tidak tayang) sudah tercapai.
          if (res.status !== 409) throw new Error(data.error ?? "Gagal menyembunyikan postingan.");
        }
      } else if (report.comment) {
        const res = await fetch(`/api/admin/feed/comments/${report.comment.id}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "hide", reason: "Disembunyikan dari laporan user" }),
        });
        if (!res.ok) {
          const data = await res.json().catch(() => ({}));
          if (res.status !== 409) throw new Error(data.error ?? "Gagal menyembunyikan komentar.");
        }
      }
      await setReportStatus(report.id, "resolve");
      await refetch();
    } catch (err) {
      window.alert(err instanceof Error ? err.message : "Gagal memproses laporan.");
    } finally {
      setBusyId(null);
    }
  }

  async function resolveOnly(reportId: string) {
    setBusyId(reportId);
    try {
      await setReportStatus(reportId, "resolve");
      await refetch();
    } catch (err) {
      window.alert(err instanceof Error ? err.message : "Gagal memperbarui laporan.");
    } finally {
      setBusyId(null);
    }
  }

  // Hapus ke Sampah — soft-delete (masih bisa di-restore 30 hari dari tab
  // Sampah di /admin/feed), lalu tandai laporan selesai. Untuk pelanggaran
  // berat/jelas; beda dari Sembunyikan yang cuma menonaktifkan tampilan.
  async function deleteAndResolve(report: ReportItem) {
    const targetLabel = report.post ? "postingan" : "komentar";
    if (
      !window.confirm(
        `Pindahkan ${targetLabel} ini ke Sampah? Masih bisa dipulihkan dari tab Sampah selama 30 hari.`,
      )
    ) {
      return;
    }
    setBusyId(report.id);
    try {
      if (report.post) {
        const res = await fetch(`/api/admin/feed/posts/${report.post.id}`, {
          method: "DELETE",
        });
        if (!res.ok) {
          const data = await res.json().catch(() => ({}));
          if (res.status !== 404) throw new Error(data.error ?? "Gagal menghapus postingan.");
        }
      } else if (report.comment) {
        const res = await fetch(`/api/admin/feed/comments/${report.comment.id}`, {
          method: "DELETE",
        });
        if (!res.ok) {
          const data = await res.json().catch(() => ({}));
          if (res.status !== 404) throw new Error(data.error ?? "Gagal menghapus komentar.");
        }
      }
      await setReportStatus(report.id, "resolve");
      await refetch();
    } catch (err) {
      window.alert(err instanceof Error ? err.message : "Gagal menghapus konten.");
    } finally {
      setBusyId(null);
    }
  }

  async function dismiss(reportId: string) {
    if (!window.confirm("Tandai laporan ini sebagai tidak melanggar?")) return;
    setBusyId(reportId);
    try {
      await setReportStatus(reportId, "dismiss");
      await refetch();
    } catch (err) {
      window.alert(err instanceof Error ? err.message : "Gagal memperbarui laporan.");
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="space-y-4">
      <PageHeader
        title="Moderasi Laporan"
        subtitle={
          counts.pending > 0
            ? `${counts.pending} laporan menunggu ditinjau`
            : "Antrean bersih — tidak ada laporan menunggu"
        }
        actions={
          <Button href="/admin/feed" variant="secondary" size="sm">
            Lihat semua post
          </Button>
        }
      />

      <nav role="tablist" aria-label="Filter status laporan" className="-mx-1 flex gap-1.5 overflow-x-auto px-1 py-1">
        {TABS.map((t) => {
          const active = tab === t.value;
          const badge = t.value === "pending" && counts.pending > 0 ? counts.pending : null;
          return (
            <button
              key={t.value}
              type="button"
              role="tab"
              aria-selected={active}
              onClick={() => setTab(t.value)}
              className={`flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-bold transition ${
                active
                  ? "border-natalo-600 bg-natalo-600 text-white"
                  : "border-zinc-200 bg-white text-zinc-600 hover:border-zinc-300 hover:bg-zinc-50"
              }`}
            >
              {t.label}
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

      {loading && <p className="py-12 text-center text-xs font-bold text-zinc-400">Memuat...</p>}
      {error && (
        <p className="rounded-2xl bg-red-50 p-3 text-center text-sm font-bold text-red-700">{error}</p>
      )}
      {!loading && !error && items.length === 0 && (
        <EmptyState
          icon={tab === "pending" ? "✅" : "🗂️"}
          title={tab === "pending" ? "Tidak ada laporan menunggu" : "Belum ada riwayat di sini"}
          description={
            tab === "pending"
              ? "Semua laporan sudah ditinjau. Laporan baru dari user akan muncul di sini."
              : "Laporan yang sudah diselesaikan atau diabaikan akan tercatat di tab ini."
          }
        />
      )}

      {!loading && !error && items.length > 0 && (
        <div className="space-y-2.5">
          {items.map((report) => (
            <ReportCard
              key={report.id}
              report={report}
              busy={busyId === report.id}
              showActions={report.status === "PENDING"}
              onHideAndResolve={() => hideAndResolve(report)}
              onDeleteAndResolve={() => deleteAndResolve(report)}
              onResolveOnly={() => resolveOnly(report.id)}
              onDismiss={() => dismiss(report.id)}
            />
          ))}
        </div>
      )}

      {hasMore && !loading && (
        <button
          type="button"
          onClick={loadMore}
          disabled={loadingMore}
          className="w-full rounded-full border border-zinc-200 bg-white py-3 text-xs font-extrabold text-zinc-700 transition hover:bg-zinc-50 disabled:opacity-50"
        >
          {loadingMore ? "Memuat..." : "Muat lebih banyak"}
        </button>
      )}
    </div>
  );
}

const POST_STATUS_META: Record<string, { text: string; variant: BadgeVariant }> = {
  PENDING_REVIEW: { text: "Menunggu review", variant: "warning" },
  ACTIVE: { text: "Tayang", variant: "success" },
  REJECTED: { text: "Ditolak", variant: "danger" },
  HIDDEN: { text: "Disembunyikan", variant: "neutral" },
};

const REPORT_STATUS_META: Record<ReportStatus, { text: string; variant: BadgeVariant }> = {
  PENDING: { text: "Menunggu", variant: "warning" },
  RESOLVED: { text: "Diselesaikan", variant: "success" },
  DISMISSED: { text: "Diabaikan", variant: "neutral" },
};

function ReportCard({
  report,
  busy,
  showActions,
  onHideAndResolve,
  onDeleteAndResolve,
  onResolveOnly,
  onDismiss,
}: {
  report: ReportItem;
  busy: boolean;
  showActions: boolean;
  onHideAndResolve: () => void;
  onDeleteAndResolve: () => void;
  onResolveOnly: () => void;
  onDismiss: () => void;
}) {
  const reasonMeta = REASON_META[report.reason] ?? REASON_META.OTHER;
  const { subReason, note } = parseDetail(report.detail);
  const isPostReport = Boolean(report.post);
  const targetGone = isPostReport ? Boolean(report.post?.deletedAt) : false;

  return (
    <div className="overflow-hidden rounded-2xl border border-zinc-200 bg-white p-3.5">
      <div className="flex items-start gap-3">
        {/* Target preview thumbnail */}
        <div className="relative h-16 w-14 shrink-0 overflow-hidden rounded-lg bg-zinc-100">
          {isPostReport && report.post?.thumbnailUrl ? (
            <Image src={report.post.thumbnailUrl} alt="" fill sizes="52px" className="object-cover" />
          ) : (
            <div className="grid h-full place-items-center text-lg">{isPostReport ? "🎬" : "💬"}</div>
          )}
        </div>

        <div className="min-w-0 flex-1">
          {/* Reason + report status row */}
          <div className="flex flex-wrap items-center gap-1.5">
            <Badge variant={reasonMeta.variant}>{reasonMeta.text}</Badge>
            {report.status !== "PENDING" && (
              <Badge variant={REPORT_STATUS_META[report.status].variant}>
                {REPORT_STATUS_META[report.status].text}
              </Badge>
            )}
            <span className="text-[11px] text-zinc-400">{timeAgo(report.createdAt)}</span>
          </div>

          {/* Who reported */}
          <p className="mt-1 text-xs text-zinc-500">
            Dilaporkan oleh <span className="font-bold text-zinc-700">{report.reporter?.name ?? "Pengguna"}</span>
            {subReason && subReason !== report.reason.toLowerCase() && (
              <> · alasan spesifik: <span className="italic">{subReason}</span></>
            )}
          </p>

          {/* Target content */}
          {isPostReport && report.post && (
            <div className="mt-1.5 flex items-center gap-1.5">
              <p className="min-w-0 truncate text-sm font-bold text-zinc-900">{report.post.title}</p>
              <Badge variant={POST_STATUS_META[report.post.status]?.variant ?? "neutral"} size="sm">
                {targetGone ? "Dihapus" : POST_STATUS_META[report.post.status]?.text ?? report.post.status}
              </Badge>
            </div>
          )}
          {isPostReport && report.post && (
            <p className="mt-0.5 truncate text-[11px] text-zinc-400">oleh {report.post.author.name}</p>
          )}
          {!isPostReport && report.comment && (
            <div className="mt-1.5">
              <p className="line-clamp-2 rounded-lg bg-zinc-50 px-2.5 py-1.5 text-sm text-zinc-700">
                "{report.comment.content}"
              </p>
              <p className="mt-0.5 text-[11px] text-zinc-400">
                komentar oleh {report.comment.author.name}
                {report.comment.isHidden && (
                  <>
                    {" "}·{" "}
                    <span className="font-bold text-emerald-600">sudah disembunyikan</span>
                  </>
                )}
              </p>
            </div>
          )}

          {note && (
            <p className="mt-1.5 line-clamp-2 rounded-lg bg-amber-50 px-2.5 py-1.5 text-[11px] italic text-amber-800">
              Catatan pelapor: "{note}"
            </p>
          )}
        </div>

        {/* Open target in new tab */}
        {isPostReport && report.post && !targetGone && (
          <Link
            href={`/admin/feed/${report.post.id}/edit`}
            target="_blank"
            aria-label="Buka postingan di admin"
            title="Buka postingan di admin"
            className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-zinc-100 text-zinc-600 transition hover:bg-zinc-200"
          >
            <FiExternalLink className="h-3.5 w-3.5" />
          </Link>
        )}
      </div>

      {showActions && (
        <div className="mt-3 flex flex-wrap gap-1.5 border-t border-zinc-100 pt-3">
          <button
            type="button"
            onClick={onHideAndResolve}
            disabled={busy || targetGone}
            className="rounded-full bg-amber-500 px-3 py-1.5 text-[11px] font-bold text-white transition hover:bg-amber-600 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isPostReport ? "Sembunyikan postingan" : "Sembunyikan komentar"}
          </button>
          <button
            type="button"
            onClick={onDeleteAndResolve}
            disabled={busy || targetGone}
            className="rounded-full bg-red-600 px-3 py-1.5 text-[11px] font-bold text-white transition hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Hapus ke Sampah
          </button>
          <button
            type="button"
            onClick={onResolveOnly}
            disabled={busy}
            className="rounded-full bg-zinc-200 px-3 py-1.5 text-[11px] font-bold text-zinc-700 transition hover:bg-zinc-300 disabled:opacity-50"
          >
            Selesai tanpa tindakan
          </button>
          <button
            type="button"
            onClick={onDismiss}
            disabled={busy}
            className="rounded-full bg-zinc-100 px-3 py-1.5 text-[11px] font-bold text-zinc-500 transition hover:bg-zinc-200 disabled:opacity-50"
          >
            Bukan pelanggaran
          </button>
        </div>
      )}
    </div>
  );
}
