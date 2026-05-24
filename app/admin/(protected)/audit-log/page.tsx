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
import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { AdminAction } from "@/lib/admin-audit";

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

const ACTION_COLORS: Record<string, string> = {
  [AdminAction.REFUND_ISSUED]: "bg-amber-100 text-amber-800 ring-amber-200",
  [AdminAction.REFUND_ITEM_OOS]: "bg-amber-100 text-amber-800 ring-amber-200",
  [AdminAction.ORDER_CANCELLED]: "bg-red-100 text-red-700 ring-red-200",
  [AdminAction.ORDER_MARK_PAID]: "bg-emerald-100 text-emerald-700 ring-emerald-200",
  [AdminAction.VOUCHER_CREATED]: "bg-blue-100 text-blue-700 ring-blue-200",
  [AdminAction.VOUCHER_UPDATED]: "bg-blue-100 text-blue-700 ring-blue-200",
  [AdminAction.VOUCHER_DELETED]: "bg-red-100 text-red-700 ring-red-200",
  [AdminAction.USER_ROLE_CHANGED]: "bg-purple-100 text-purple-700 ring-purple-200",
  [AdminAction.USER_DELETED]: "bg-red-100 text-red-700 ring-red-200",
  [AdminAction.PUSH_BROADCAST]: "bg-blue-100 text-blue-700 ring-blue-200",
};

function actionLabel(action: string): string {
  return ACTION_LABELS[action] ?? action;
}

function actionColor(action: string): string {
  return (
    ACTION_COLORS[action] ?? "bg-zinc-100 text-zinc-700 ring-zinc-200"
  );
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
    <div className="mx-auto max-w-6xl px-4 py-6">
      <div className="mb-4 flex items-center gap-3">
        <Link
          href="/admin/dashboard"
          className="text-sm text-zinc-600 hover:text-zinc-900"
        >
          ← Dashboard
        </Link>
      </div>

      <div className="mb-5">
        <h1 className="text-xl font-bold text-zinc-950">Audit Log</h1>
        <p className="mt-1 text-sm text-zinc-600">
          Kronologi semua tindakan admin. Pakai untuk verifikasi, dispute,
          dan tracking staff. Newest first.
        </p>
      </div>

      {/* Filters */}
      <form
        action="/admin/audit-log"
        method="get"
        className="mb-5 grid gap-3 rounded-2xl border border-zinc-200 bg-white p-4 md:grid-cols-4"
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
          <button
            type="submit"
            className="rounded-lg bg-blue-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-blue-700"
          >
            Apply filter
          </button>
          {(actorId || actionFilter || targetFilter || searchQuery) && (
            <Link
              href="/admin/audit-log"
              className="rounded-lg border border-zinc-300 bg-white px-3 py-1.5 text-sm font-semibold text-zinc-700 hover:bg-zinc-50"
            >
              Reset
            </Link>
          )}
          <span className="ml-auto text-xs text-zinc-500">
            Showing {sliced.length} entries
          </span>
        </div>
      </form>

      {/* Log feed */}
      <div className="overflow-hidden rounded-2xl border border-zinc-200 bg-white">
        {sliced.length === 0 ? (
          <div className="p-8 text-center text-sm text-zinc-500">
            Belum ada log untuk filter ini.
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-zinc-50 text-xs uppercase text-zinc-500">
              <tr>
                <th className="px-3 py-2 text-left">Waktu</th>
                <th className="px-3 py-2 text-left">Admin</th>
                <th className="px-3 py-2 text-left">Action</th>
                <th className="px-3 py-2 text-left">Summary</th>
                <th className="px-3 py-2 text-left">Target</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-100">
              {sliced.map((log) => (
                <tr key={log.id} className="hover:bg-zinc-50/60">
                  <td className="px-3 py-2 align-top text-xs whitespace-nowrap text-zinc-600">
                    {formatDateTime(log.createdAt)}
                  </td>
                  <td className="px-3 py-2 align-top text-xs font-semibold text-zinc-900">
                    {log.actor?.name ?? log.actorUserId.slice(0, 8)}
                  </td>
                  <td className="px-3 py-2 align-top">
                    <span
                      className={`inline-block rounded-full px-2 py-0.5 text-[10px] font-bold uppercase ring-1 ${actionColor(log.action)}`}
                    >
                      {actionLabel(log.action)}
                    </span>
                  </td>
                  <td className="px-3 py-2 align-top text-sm text-zinc-800">
                    {log.summary}
                    {log.metadata !== null && (
                      <details className="mt-1 text-[11px] text-zinc-500">
                        <summary className="cursor-pointer">
                          Detail metadata
                        </summary>
                        <pre className="mt-1 max-w-md overflow-x-auto rounded bg-zinc-100 p-2 text-[10px]">
                          {JSON.stringify(log.metadata, null, 2)}
                        </pre>
                      </details>
                    )}
                  </td>
                  <td className="px-3 py-2 align-top text-xs">
                    <div className="text-zinc-600">{log.targetType}</div>
                    <div className="font-mono text-[10px] text-zinc-500">
                      {log.targetId.slice(0, 12)}…
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Pagination */}
      {nextCursor && (
        <div className="mt-4 flex justify-center">
          <Link
            href={buildFilterUrl({ cursor: nextCursor })}
            className="rounded-lg border border-zinc-300 bg-white px-4 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-50"
          >
            Load 50 lagi →
          </Link>
        </div>
      )}
    </div>
  );
}
