import { NextRequest, NextResponse } from "next/server";
import type { Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

/**
 * GET /api/admin/abuse-flags
 *
 * List AbuseFlag rows untuk admin review queue.
 *
 * Query:
 *   - `status` — "OPEN" (default) | "REVIEWED" | "DISMISSED" | "BLOCKED" | "ALL"
 *   - `severity` — "LOW" | "MEDIUM" | "HIGH"
 *   - `cursor` — id row terakhir
 *   - `limit` — default 30, max 100
 *
 * Response: { items: [...], nextCursor, counts: { OPEN, REVIEWED, DISMISSED, BLOCKED } }
 *
 * Sort: severity HIGH first, lalu createdAt DESC.
 */
export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const sp = request.nextUrl.searchParams;
  const status = sp.get("status")?.trim() ?? "OPEN";
  const severity = sp.get("severity")?.trim() || null;
  const cursor = sp.get("cursor") || null;
  const limit = Math.min(Math.max(parseInt(sp.get("limit") ?? "30", 10), 1), 100);

  const where: Prisma.AbuseFlagWhereInput = {};
  if (status !== "ALL") where.status = status;
  if (severity && ["LOW", "MEDIUM", "HIGH"].includes(severity)) {
    where.severity = severity;
  }

  // High severity first untuk OPEN queue — admin lihat yang urgent dulu.
  // Untuk filter status lain, urutan by createdAt cukup.
  const orderBy: Prisma.AbuseFlagOrderByWithRelationInput[] =
    status === "OPEN"
      ? [{ severity: "desc" }, { createdAt: "desc" }, { id: "desc" }]
      : [{ createdAt: "desc" }, { id: "desc" }];

  const [rows, openCount, reviewedCount, dismissedCount, blockedCount] =
    await Promise.all([
      prisma.abuseFlag.findMany({
        where,
        orderBy,
        take: limit + 1,
        ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
        select: {
          id: true,
          ruleCode: true,
          severity: true,
          status: true,
          details: true,
          adminNote: true,
          createdAt: true,
          reviewedAt: true,
          user: {
            select: { id: true, name: true, email: true, phoneNumber: true },
          },
          reviewedBy: {
            select: { id: true, name: true, email: true },
          },
        },
      }),
      prisma.abuseFlag.count({ where: { status: "OPEN" } }),
      prisma.abuseFlag.count({ where: { status: "REVIEWED" } }),
      prisma.abuseFlag.count({ where: { status: "DISMISSED" } }),
      prisma.abuseFlag.count({ where: { status: "BLOCKED" } }),
    ]);

  const hasMore = rows.length > limit;
  const items = hasMore ? rows.slice(0, limit) : rows;
  const nextCursor = hasMore ? items[items.length - 1].id : null;

  return NextResponse.json({
    items,
    nextCursor,
    counts: {
      OPEN: openCount,
      REVIEWED: reviewedCount,
      DISMISSED: dismissedCount,
      BLOCKED: blockedCount,
    },
  });
}
