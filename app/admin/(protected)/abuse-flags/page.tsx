/**
 * Admin Abuse Flag Review — list flagged user + bulk actions
 *
 * Default view: status=OPEN flags sorted by severity HIGH first, newest.
 * Filter dropdown: status (OPEN/REVIEWED/DISMISSED/BLOCKED), rule code,
 * severity.
 *
 * Per-row action (via server action `reviewAbuseFlag`):
 *   - "Tinjau" → status REVIEWED + admin note (monitoring confirmed)
 *   - "Dismiss" → status DISMISSED (false positive, gak abuse beneran)
 *   - "Block user" → set user role + status BLOCKED (extreme — disable
 *     login + invalidate tokenVersion)
 *
 * Audit logged via admin-audit (action: USER_ROLE_CHANGED untuk block,
 * generic ABUSE_FLAG_REVIEWED untuk lainnya).
 */
import Link from "next/link";
import { prisma } from "@/lib/prisma";
import { AbuseRule } from "@/lib/abuse-detection";
import { reviewAbuseFlag } from "./actions";
import {
  PageHeader,
  StatCard,
  EmptyState,
  Badge,
  type BadgeVariant,
} from "@/components/admin/ui";

const SEVERITY_VARIANT: Record<string, BadgeVariant> = {
  HIGH: "danger",
  MEDIUM: "warning",
  LOW: "neutral",
};

const STATUS_VARIANT: Record<string, BadgeVariant> = {
  OPEN: "danger",
  REVIEWED: "info",
  DISMISSED: "neutral",
  BLOCKED: "purple",
};

const RULE_LABELS: Record<string, string> = {
  [AbuseRule.BURST_VOUCHER_CLAIM]: "Burst Voucher Claim",
  [AbuseRule.GMAIL_ALIAS_DUPLICATE]: "Gmail Alias Duplicate",
  [AbuseRule.DUPLICATE_SHIPPING_ADDRESS]: "Duplicate Shipping Address",
  [AbuseRule.NEW_ACCOUNT_INSTANT_CLAIM]: "Instant Claim Saat Register",
};

function formatDateTime(d: Date): string {
  return new Intl.DateTimeFormat("id-ID", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(d);
}

export default async function AbuseFlagsPage({
  searchParams,
}: {
  searchParams: Promise<{
    status?: string;
    rule?: string;
    severity?: string;
  }>;
}) {
  const sp = await searchParams;
  const statusFilter = sp.status ?? "OPEN";
  const ruleFilter = sp.rule;
  const severityFilter = sp.severity;

  const where: Record<string, unknown> = {};
  if (statusFilter && statusFilter !== "ALL") where.status = statusFilter;
  if (ruleFilter) where.ruleCode = ruleFilter;
  if (severityFilter) where.severity = severityFilter;

  // Severity ordering: HIGH > MEDIUM > LOW (Postgres alphabetical
  // happens to put HIGH > MEDIUM > LOW kalau di-cast, but defensive
  // we sort secondary by createdAt desc).
  const [flags, openCount, reviewedCount, dismissedCount, blockedCount] =
    await Promise.all([
      prisma.abuseFlag.findMany({
        where,
        orderBy: [{ severity: "asc" }, { createdAt: "desc" }],
        take: 100,
        include: {
          user: {
            select: {
              id: true,
              name: true,
              email: true,
              phone: true,
              username: true,
              createdAt: true,
            },
          },
          reviewedBy: { select: { name: true } },
        },
      }),
      prisma.abuseFlag.count({ where: { status: "OPEN" } }),
      prisma.abuseFlag.count({ where: { status: "REVIEWED" } }),
      prisma.abuseFlag.count({ where: { status: "DISMISSED" } }),
      prisma.abuseFlag.count({ where: { status: "BLOCKED" } }),
    ]);

  return (
    <div className="mx-auto max-w-6xl px-4 py-5 md:py-10">
      <PageHeader
        title="🚨 Abuse Flags"
        subtitle="Cron daily scan suspicious pattern (burst claim, gmail alias, alamat duplikat, instant claim). Review flagged user + decide action. Daily 03:00 WIB."
        actions={
          <Link
            href="/admin/dashboard"
            className="inline-flex items-center gap-1.5 rounded-full border border-zinc-200 bg-white px-3.5 py-2 text-xs font-bold text-zinc-700 transition hover:border-zinc-400 hover:bg-zinc-50"
          >
            ← Dashboard
          </Link>
        }
      />

      {/* Status counts — pakai StatCard primitives */}
      <section className="mt-6 grid grid-cols-2 gap-3 md:grid-cols-4">
        <StatCard
          label="Open (review queue)"
          value={openCount}
          helper="Belum di-review"
          href="/admin/abuse-flags?status=OPEN"
          variant="danger"
        />
        <StatCard
          label="Reviewed"
          value={reviewedCount}
          helper="Sudah ditinjau"
          href="/admin/abuse-flags?status=REVIEWED"
          variant="primary"
        />
        <StatCard
          label="Dismissed"
          value={dismissedCount}
          helper="False positive"
          href="/admin/abuse-flags?status=DISMISSED"
          variant="default"
        />
        <StatCard
          label="Blocked"
          value={blockedCount}
          helper="User di-block"
          href="/admin/abuse-flags?status=BLOCKED"
          variant="warning"
        />
      </section>

      {/* Filter form */}
      <form
        action="/admin/abuse-flags"
        method="get"
        className="mt-6 mb-5 grid gap-3 rounded-2xl border border-zinc-200 bg-white p-4 md:grid-cols-3 md:p-5"
      >
        <div>
          <label className="block text-xs font-semibold text-zinc-700">
            Status
          </label>
          <select
            name="status"
            defaultValue={statusFilter}
            className="mt-1 w-full rounded-lg border border-zinc-300 px-2.5 py-1.5 text-sm"
          >
            <option value="ALL">Semua</option>
            <option value="OPEN">Open</option>
            <option value="REVIEWED">Reviewed</option>
            <option value="DISMISSED">Dismissed</option>
            <option value="BLOCKED">Blocked</option>
          </select>
        </div>
        <div>
          <label className="block text-xs font-semibold text-zinc-700">
            Rule
          </label>
          <select
            name="rule"
            defaultValue={ruleFilter ?? ""}
            className="mt-1 w-full rounded-lg border border-zinc-300 px-2.5 py-1.5 text-sm"
          >
            <option value="">Semua rule</option>
            {Object.entries(RULE_LABELS).map(([code, label]) => (
              <option key={code} value={code}>
                {label}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs font-semibold text-zinc-700">
            Severity
          </label>
          <select
            name="severity"
            defaultValue={severityFilter ?? ""}
            className="mt-1 w-full rounded-lg border border-zinc-300 px-2.5 py-1.5 text-sm"
          >
            <option value="">Semua severity</option>
            <option value="HIGH">High</option>
            <option value="MEDIUM">Medium</option>
            <option value="LOW">Low</option>
          </select>
        </div>
        <div className="md:col-span-3">
          <button
            type="submit"
            className="rounded-full bg-natalo-600 px-4 py-2 text-sm font-bold text-white shadow-sm transition hover:bg-natalo-700"
          >
            Apply filter
          </button>
        </div>
      </form>

      {/* Flag list */}
      {flags.length === 0 ? (
        <div className="rounded-2xl border border-zinc-200 bg-white">
          <EmptyState
            icon={statusFilter === "OPEN" ? "🎉" : "🔍"}
            title={
              statusFilter === "OPEN"
                ? "Tidak ada open flag — sistem clean!"
                : "Tidak ada flag untuk filter ini"
            }
            description={
              statusFilter === "OPEN"
                ? "Cron scan harian belum nge-detect pola abuse. Aman!"
                : "Coba reset filter atau pilih status lain."
            }
            size="full"
          />
        </div>
      ) : (
        <div className="space-y-3">
          {flags.map((flag) => (
            <FlagCard key={flag.id} flag={flag} />
          ))}
        </div>
      )}
    </div>
  );
}

type FlagWithUser = Awaited<ReturnType<typeof prisma.abuseFlag.findMany>>[number] & {
  user: {
    id: string;
    name: string;
    email: string | null;
    phone: string | null;
    username: string | null;
    createdAt: Date;
  };
  reviewedBy: { name: string } | null;
};

function FlagCard({ flag }: { flag: FlagWithUser }) {
  const reviewAction = reviewAbuseFlag.bind(null, flag.id);
  return (
    <article className="rounded-2xl border border-zinc-200 bg-white p-4 md:p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant={SEVERITY_VARIANT[flag.severity] ?? "neutral"}>
            {flag.severity}
          </Badge>
          <Badge variant={STATUS_VARIANT[flag.status] ?? "neutral"}>
            {flag.status}
          </Badge>
          <span className="text-sm font-bold text-zinc-900">
            {RULE_LABELS[flag.ruleCode] ?? flag.ruleCode}
          </span>
        </div>
        <span className="text-xs text-zinc-500">
          {formatDateTime(flag.createdAt)}
        </span>
      </div>

      {/* User info */}
      <div className="mt-3 rounded-lg bg-zinc-50 p-3 text-sm">
        <div className="flex flex-wrap items-baseline gap-2">
          <span className="font-bold text-zinc-900">{flag.user.name}</span>
          {flag.user.username && (
            <span className="text-zinc-600">@{flag.user.username}</span>
          )}
        </div>
        <div className="mt-1 grid gap-x-3 gap-y-0.5 text-xs text-zinc-600 sm:grid-cols-3">
          <span>📧 {flag.user.email ?? "—"}</span>
          <span>📱 {flag.user.phone ?? "—"}</span>
          <span>👤 Daftar: {formatDateTime(flag.user.createdAt)}</span>
        </div>
      </div>

      {/* Detail metadata */}
      {flag.details !== null && (
        <details className="mt-3 text-xs">
          <summary className="cursor-pointer text-zinc-600">
            Lihat detail data
          </summary>
          <pre className="mt-1 max-w-full overflow-x-auto rounded bg-zinc-100 p-2 text-[10px] text-zinc-700">
            {JSON.stringify(flag.details, null, 2)}
          </pre>
        </details>
      )}

      {/* Review history */}
      {flag.reviewedBy && flag.reviewedAt && (
        <div className="mt-3 rounded-lg border border-blue-200 bg-blue-50 p-2.5 text-xs">
          <p className="font-semibold text-blue-900">
            Ditinjau oleh {flag.reviewedBy.name} pada{" "}
            {formatDateTime(flag.reviewedAt)}
          </p>
          {flag.adminNote && (
            <p className="mt-0.5 text-blue-800">"{flag.adminNote}"</p>
          )}
        </div>
      )}

      {/* Actions (kalau status OPEN) */}
      {flag.status === "OPEN" && (
        <form action={reviewAction} className="mt-3 flex flex-wrap gap-2">
          <input
            type="text"
            name="adminNote"
            placeholder="Catatan opsional..."
            maxLength={500}
            className="flex-1 min-w-[200px] rounded-lg border border-zinc-300 px-2.5 py-1.5 text-xs"
          />
          <button
            type="submit"
            name="action"
            value="REVIEWED"
            className="rounded-lg border border-blue-300 bg-blue-50 px-3 py-1.5 text-xs font-semibold text-blue-800 hover:bg-blue-100"
          >
            Tinjau (Monitoring)
          </button>
          <button
            type="submit"
            name="action"
            value="DISMISSED"
            className="rounded-lg border border-zinc-300 bg-white px-3 py-1.5 text-xs font-semibold text-zinc-700 hover:bg-zinc-50"
          >
            Dismiss (False Positive)
          </button>
          <button
            type="submit"
            name="action"
            value="BLOCKED"
            className="rounded-lg border border-red-300 bg-red-50 px-3 py-1.5 text-xs font-semibold text-red-700 hover:bg-red-100"
          >
            🚫 Block User
          </button>
        </form>
      )}
    </article>
  );
}
