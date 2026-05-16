import type { FeedPostStatus } from "@prisma/client";

export type MyFeedFilter = "all" | "pending" | "active" | "rejected";

export const MY_FEED_VISIBLE_STATUSES = [
  "PENDING_REVIEW",
  "ACTIVE",
  "REJECTED",
] as const satisfies readonly FeedPostStatus[];

export const MY_FEED_STATUS_BY_FILTER: Record<
  Exclude<MyFeedFilter, "all">,
  FeedPostStatus
> = {
  pending: "PENDING_REVIEW",
  active: "ACTIVE",
  rejected: "REJECTED",
};

export function normalizeMyFeedFilter(value: string | undefined): MyFeedFilter {
  if (value === "pending" || value === "active" || value === "rejected") {
    return value;
  }
  return "all";
}

export function myFeedStatusMeta(status: FeedPostStatus) {
  if (status === "ACTIVE") {
    return {
      label: "Tayang",
      description: "Sudah tayang di Feed",
      badgeClass: "bg-emerald-100 text-emerald-700 ring-emerald-200",
      panelClass: "border-emerald-100 bg-emerald-50/70 text-emerald-900",
    };
  }

  if (status === "REJECTED") {
    return {
      label: "Ditolak",
      description: "Ditolak oleh admin",
      badgeClass: "bg-red-100 text-red-700 ring-red-200",
      panelClass: "border-red-100 bg-red-50/80 text-red-900",
    };
  }

  return {
    label: "Menunggu Review",
    description: "Sedang menunggu review admin",
    badgeClass: "bg-amber-100 text-amber-800 ring-amber-200",
    panelClass: "border-amber-100 bg-amber-50/80 text-amber-950",
  };
}

export function formatFeedDuration(seconds: number | null | undefined) {
  const total = Math.max(0, Math.round(seconds ?? 0));
  const minutes = Math.floor(total / 60);
  const rest = total % 60;
  return `${String(minutes).padStart(2, "0")}:${String(rest).padStart(2, "0")}`;
}

export function formatFeedPostDate(date: Date) {
  return new Intl.DateTimeFormat("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Asia/Jakarta",
  })
    .format(date)
    .replace(".", ":");
}
