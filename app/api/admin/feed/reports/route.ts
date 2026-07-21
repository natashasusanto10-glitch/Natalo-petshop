/**
 * GET /api/admin/feed/reports?status=...&cursor=...
 *
 * Admin moderation queue untuk user-submitted reports (FeedReport table).
 * Filter status: pending (default) / resolved / dismissed / all.
 *
 * Sort PENDING oldest-first (FIFO supaya report lama tidak terlupakan),
 * lainnya newest-first. Include context post/comment + reporter info
 * supaya admin bisa decide tanpa extra fetch.
 *
 * Pagination cursor-based — page 20.
 */
import { NextRequest, NextResponse } from "next/server";
import type { FeedReportStatus, Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { signBunnyUrl } from "@/lib/feed/bunny";

const PAGE_SIZE = 20;

type StatusFilter = "pending" | "resolved" | "dismissed" | "all";
const VALID_FILTERS: StatusFilter[] = ["pending", "resolved", "dismissed", "all"];

const STATUS_BY_FILTER: Record<Exclude<StatusFilter, "all">, FeedReportStatus> = {
  pending: "PENDING",
  resolved: "RESOLVED",
  dismissed: "DISMISSED",
};

export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const url = new URL(request.url);
  const rawFilter = url.searchParams.get("status") ?? "pending";
  const filter: StatusFilter = (VALID_FILTERS as string[]).includes(rawFilter)
    ? (rawFilter as StatusFilter)
    : "pending";
  const cursor = url.searchParams.get("cursor") || null;

  const where: Prisma.FeedReportWhereInput =
    filter === "all"
      ? {}
      : { status: STATUS_BY_FILTER[filter] };

  // PENDING queue oldest-first untuk FIFO. RESOLVED/DISMISSED newest-first
  // (recent activity di atas, history scroll bawah).
  const orderBy: Prisma.FeedReportOrderByWithRelationInput =
    filter === "pending"
      ? { createdAt: "asc" }
      : { createdAt: "desc" };

  const reports = await prisma.feedReport.findMany({
    where,
    orderBy,
    take: PAGE_SIZE + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    include: {
      reporter: {
        select: { id: true, name: true, profilePhotoUrl: true },
      },
      post: {
        select: {
          id: true,
          title: true,
          description: true,
          thumbnailUrl: true,
          kind: true,
          status: true,
          deletedAt: true,
          authorId: true,
          author: { select: { id: true, name: true } },
        },
      },
      comment: {
        select: {
          id: true,
          content: true,
          isHidden: true,
          postId: true,
          authorId: true,
          author: { select: { id: true, name: true } },
        },
      },
    },
  });

  const hasMore = reports.length > PAGE_SIZE;
  const sliced = hasMore ? reports.slice(0, PAGE_SIZE) : reports;
  const nextCursor = hasMore ? sliced[sliced.length - 1].id : null;

  // Counts per status untuk badge di admin nav.
  const [pendingCount, resolvedCount, dismissedCount] = await Promise.all([
    prisma.feedReport.count({ where: { status: "PENDING" } }),
    prisma.feedReport.count({ where: { status: "RESOLVED" } }),
    prisma.feedReport.count({ where: { status: "DISMISSED" } }),
  ]);

  return NextResponse.json({
    reports: sliced.map((r) => ({
      id: r.id,
      reason: r.reason,
      detail: r.detail,
      status: r.status,
      createdAt: r.createdAt.toISOString(),
      resolvedAt: r.resolvedAt?.toISOString() ?? null,
      resolvedById: r.resolvedById,
      reporter: r.reporter
        ? {
            id: r.reporter.id,
            name: r.reporter.name,
            profilePhotoUrl: r.reporter.profilePhotoUrl,
          }
        : null,
      post: r.post
        ? {
            id: r.post.id,
            title: r.post.title,
            description: r.post.description,
            thumbnailUrl: signBunnyUrl(r.post.thumbnailUrl),
            kind: r.post.kind,
            status: r.post.status,
            deletedAt: r.post.deletedAt?.toISOString() ?? null,
            author: r.post.author,
          }
        : null,
      comment: r.comment
        ? {
            id: r.comment.id,
            content: r.comment.content,
            isHidden: r.comment.isHidden,
            postId: r.comment.postId,
            author: r.comment.author,
          }
        : null,
    })),
    nextCursor,
    counts: {
      pending: pendingCount,
      resolved: resolvedCount,
      dismissed: dismissedCount,
    },
    filter,
  });
}
