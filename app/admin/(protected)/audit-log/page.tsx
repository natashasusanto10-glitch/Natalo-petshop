/**
 * Admin Audit Log — feed kronologis semua action critical yang admin
 * lakukan. Dipakai untuk compliance, dispute resolution, rogue admin
 * detection, dan onboarding staff baru.
 *
 * Query params:
 *   - actor: filter by admin userId
 *   - action: filter by action type (e.g. REFUND_ISSUED)
 *   - target: filter by targetType (Order, RefundCase, Voucher, dll)
 *   - q: search di summary text
 *   - cursor: pagination cursor (lastSeenId)
 *
 * Pagination cursor-based — 50 entries per page. Newest first.
 */
import { prisma } from "@/lib/prisma";
import { AdminAction } from "@/lib/admin-audit";
import {
  AdminPage,
  Button,
  PageHeader,
  EmptyState,
  Badge,
  type BadgeVariant,
} from "@/components/admin/ui";

const PAGE_SIZE = 50;

const ACTION_LABELS: Record<string, string> = {
  [AdminAction.ORDER_MARK_PAID]: "Konfirmasi Pembayaran",
  [AdminAction.ORDER_MARK_PROCESSING]: "Mulai Packing",
  [AdminAction.ORDER_MARK_READY_PICKUP]: "Siap Diambil",
  [AdminAction.ORDER_MARK_PICKED_UP]: "Sudah Diambil",
  [AdminAction.ORDER_MARK_SHIPPED]: "Dikirim",
  [AdminAction.ORDER_MARK_DELIVERED]: "Diterima",
  [AdminAction.ORDER_CANCELLED]: "Order Dibatalkan",
  [AdminAction.ORDER_SHIPMENT_CREATED]: "Buat Resi Pengiriman",
  [AdminAction.REFUND_ISSUED]: "Refund Issued",
  [AdminAction.REFUND_ITEM_OOS]: "Refund Item Kosong",
  [AdminAction.VOUCHER_CREATED]: "Voucher Dibuat",
  [AdminAction.VOUCHER_UPDATED]: "Voucher Diedit",
  [AdminAction.VOUCHER_DELETED]: "Voucher Dihapus",
  [AdminAction.USER_ROLE_CHANGED]: "User Role Diubah",
  [AdminAction.USER_DELETED]: "User Dihapus",
  [AdminAction.FEED_POST_APPROVED]: "Feed Approved",
  [AdminAction.FEED_POST_REJECTED]: "Feed Rejected",
  [AdminAction.FEED_POST_HIDDEN]: "Feed Disembunyikan",
  [AdminAction.FEED_COMMENT_HIDDEN]: "Comment Disembunyikan",
  [AdminAction.PUSH_BROADCAST]: "Broadcast Push",
};

// Map admin action → Badge variant. Refund/cancel = warning/danger,
// state change = success/info, voucher CRUD = info/danger, role/delete = purple.
const ACTION_VARIANTS: Record<string, BadgeVariant> = {
  [AdminAction.REFUND_ISSUED]: "warning",
  [AdminAction.REFUND_ITEM_OOS]: "warning",
  [AdminAction.ORDER_CANCELLED]: "danger",
  [AdminAction.ORDER_MARK_PAID]: "success",
  [AdminAction.ORDER_MARK_PROCESSING]: "info",
  [AdminAction.ORDER_MARK_SHIPPED]: "info",
  [AdminAction.ORDER_MARK_DELIVERED]: "success",
  [AdminAction.VOUCHER_CREATED]: "info",
  [AdminAction.VOUCHER_UPDATED]: "info",
  [AdminAction.VOUCHER_DELETED]: "danger",
  [AdminAction.USER_ROLE_CHANGED]: "purple",
  [AdminAction.USER_DELETED]: "danger",
  [AdminAction.PUSH_BROADCAST]: "accent",
  [AdminAction.FEED_POST_APPROVED]: "success",
  [AdminAction.FEED_POST_REJECTED]: "danger",
  [AdminAction.FEED_POST_HIDDEN]: "warning",
  [AdminAction.FEED_COMMENT_HIDDEN]: "warning",
};

function actionLabel(action: string): string {
  return ACTION_LABELS[action] ?? action;
}

function actionVariant(action: string): BadgeVariant {
  return ACTION_VARIANTS[action] ?? "neutral";
}

function formatDateTime(d: Date): string {
  return new Intl.DateTimeFormat("id-ID", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(d);
}

export default async function AdminAuditLogPage({
  searchParams,
}: {
  searchParams: Promise<{
    actor?: string;
    action?: string;
    target?: string;
    q?: string;
    cursor?: string;
  }>;
}) {
  const sp = await searchParams;
  const actorId = sp.actor;
  const actionFilter = sp.action;
  const targetFilter = sp.target;
  const searchQuery = sp.q?.trim() ?? "";
  const cursor = sp.cursor;

  const where: Record<string, unknown> = {};
  if (actorId) where.actorUserId = actorId;
  if (actionFilter) where.action = actionFilter;
  if (targetFilter) where.targetType = targetFilter;
  if (searchQuery) {
    where.OR = [
      { summary: { contains: searchQuery, mode: "insensitive" } },
      { targetId: { contains: searchQuery, mode: "insensitive" } },
    ];
  }

  const [logs, distinctActions, distinctTargets, distinctActors] =
    await Promise.all([
      prisma.adminActionLog.findMany({
        where,
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: PAGE_SIZE + 1,
        ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
        include: {
          actor: { select: { id: true, name: true, email: true } },
        },
      }),
      // Distinct action types yang pernah ke-record — untuk filter dropdown.
      prisma.adminActionLog.findMany({
        distinct: ["action"],
        select: { action: true },
        orderBy: { action: "asc" },
        take: 50,
      }),
      prisma.adminActionLog.findMany({
        distinct: ["targetType"],
        select: { targetType: true },
        orderBy: { targetType: "asc" },
        take: 20,
      }),
      // Distinct admin actor (max 50 — kalau lebih, list jadi panjang).
      prisma.adminActionLog.findMany({
        distinct: ["actorUserId"],
        select: {
          actorUserId: true,
          actor: { select: { name: true } },
        },
        take: 50,
      }),
    ]);

  const hasMore = logs.length > PAGE_SIZE;
  const sliced = hasMore ? logs.slice(0, PAGE_SIZE) : logs;
  const nextCursor = hasMore ? sliced[sliced.length - 1].id : null;

  // Build filter query string preserving existing params.
  const buildFilterUrl = (overrides: Record<string, string | null>) => {
    const params = new URLSearchParams();
    const next = {
      actor: actorId,
      action: actionFilter,
      target: targetFilter,
      q: searchQuery || undefined,
      ...overrides,
    };
    for (const [k, v] of Object.entries(next)) {
      if (v) params.set(k, v);
    }
    const qs = params.toString();
    return `/admin/audit-log${qs ? `?${qs}` : ""}`;
  };

  return (
    <AdminPage maxWidth="xl">
      <PageHeader
        title="Audit Log"
        subtitle="Kronologi semua tindakan admin. Pakai untuk verifikasi, dispute, dan tracking staff. Newest first."
        actions={
          <Button href="/admin/dashboard" variant="secondary" size="sm">
            ← Dashboard
          </Button>
        }
      />

      {/* Filters */}
      <form
        action="/admin/audit-log"
        method="get"
        className="mt-6 mb-5 grid gap-3 rounded-2xl border border-zinc-200 bg-white p-4 md:grid-cols-4 md:p-5"
      >
        <div>
          <label className="block text-xs font-semibold text-zinc-700">
            Admin
          </label>
          <select
            name="actor"
            defaultValue={actorId ?? ""}
            className="mt-1 w-full rounded-lg border border-zinc-300 px-2.5 py-1.5 text-sm"
          >
            <option value="">— Semua admin —</option>
            {distinctActors.map((a) => (
              <option key={a.actorUserId} value={a.actorUserId}>
                {a.actor?.name ?? a.actorUserId.slice(0, 8)}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs font-semibold text-zinc-700">
            Action type
          </label>
          <select
            name="action"
            defaultValue={actionFilter ?? ""}
            className="mt-1 w-full rounded-lg border border-zinc-300 px-2.5 py-1.5 text-sm"
          >
            <option value="">— Semua action —</option>
            {distinctActions.map((a) => (
              <option key={a.action} value={a.action}>
                {actionLabel(a.action)}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs font-semibold text-zinc-700">
            Target type
          </label>
          <select
            name="target"
            defaultValue={targetFilter ?? ""}
            className="mt-1 w-full rounded-lg border border-zinc-300 px-2.5 py-1.5 text-sm"
          >
            <option value="">— Semua —</option>
            {distinctTargets.map((t) => (
              <option key={t.targetType} value={t.targetType}>
                {t.targetType}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs font-semibold text-zinc-700">
            Cari (summary / ID)
          </label>
          <input
            type="text"
            name="q"
            defaultValue={searchQuery}
            placeholder="e.g. ORD-20260524 atau refund"
            className="mt-1 w-full rounded-lg border border-zinc-300 px-2.5 py-1.5 text-sm"
          />
        </div>
        <div className="md:col-span-4 flex items-center gap-2 pt-1">
          <Button type="submit">Apply filter</Button>
          {(actorId || actionFilter || targetFilter || searchQuery) && (
            <Button href="/admin/audit-log" variant="secondary">
              ✕ Reset
            </Button>
          )}
          <span className="ml-auto text-xs font-semibold text-zinc-500">
            Showing {sliced.length} entries
          </span>
        </div>
      </form>

      {/* Log feed */}
      <div className="overflow-hidden rounded-2xl border border-zinc-200 bg-white">
        {sliced.length === 0 ? (
          <EmptyState
            icon="📋"
            title="Belum ada log untuk filter ini"
            description="Coba reset filter atau pilih kriteria yang berbeda."
            size="full"
          />
        ) : (
          <table className="w-full text-sm">
            <thead className="border-b border-zinc-100 bg-zinc-50/50">
              <tr>
                <th className="px-4 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                  Waktu
                </th>
                <th className="px-4 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                  Admin
                </th>
                <th className="px-4 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                  Action
                </th>
                <th className="px-4 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                  Summary
                </th>
                <th className="px-4 py-3.5 text-left text-[11px] font-black uppercase tracking-wider text-zinc-500">
                  Target
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-100">
              {sliced.map((log) => {
                const initial = log.actor?.name?.[0]?.toUpperCase() ?? "?";
                return (
                  <tr key={log.id} className="transition hover:bg-natalo-50/40">
                    <td className="px-4 py-3 align-top text-xs whitespace-nowrap text-zinc-500">
                      {formatDateTime(log.createdAt)}
                    </td>
                    <td className="px-4 py-3 align-top">
                      <div className="flex items-center gap-2">
                        <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md bg-natalo-50 text-[10px] font-black text-natalo-700">
                          {initial}
                        </div>
                        <span className="text-xs font-bold text-zinc-900">
                          {log.actor?.name ?? log.actorUserId.slice(0, 8)}
                        </span>
                      </div>
                    </td>
                    <td className="px-4 py-3 align-top">
                      <Badge variant={actionVariant(log.action)}>
                        {actionLabel(log.action)}
                      </Badge>
                    </td>
                    <td className="px-4 py-3 align-top text-sm text-zinc-800">
                      {log.summary}
                      {log.metadata !== null && (
                        <details className="mt-1 text-[11px] text-zinc-500">
                          <summary className="cursor-pointer hover:text-natalo-600">
                            Detail metadata
                          </summary>
                          <pre className="mt-1 max-w-md overflow-x-auto rounded-lg bg-zinc-100 p-2 text-[10px]">
                            {JSON.stringify(log.metadata, null, 2)}
                          </pre>
                        </details>
                      )}
                    </td>
                    <td className="px-4 py-3 align-top text-xs">
                      <div className="font-bold text-zinc-700">{log.targetType}</div>
                      <div className="font-mono text-[10px] text-zinc-500">
                        {log.targetId.slice(0, 12)}…
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {/* Pagination */}
      {nextCursor && (
        <div className="mt-5 flex justify-center">
          <Button href={buildFilterUrl({ cursor: nextCursor })}>
            Load 50 lagi →
          </Button>
        </div>
      )}
    </AdminPage>
  );
}
