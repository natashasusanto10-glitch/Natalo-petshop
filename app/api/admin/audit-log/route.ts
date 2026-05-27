import { NextRequest, NextResponse } from "next/server";
import type { Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

/**
 * GET /api/admin/audit-log
 *
 * List AdminActionLog rows untuk admin mobile + web dashboard.
 *
 * Query:
 *   - `cursor` — id row terakhir, untuk pagination
 *   - `limit` — default 30, max 100
 *   - `action` — filter by action code (mis. REFUND_ISSUED)
 *   - `targetType` — filter by entity type (Order, Voucher, User, dll)
 *
 * Response: { items: [...], nextCursor: string | null }
 *
 * Sort: createdAt DESC (newest first).
 */
export async function GET(request: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const sp = request.nextUrl.searchParams;
  const cursor = sp.get("cursor") || null;
  const limit = Math.min(Math.max(parseInt(sp.get("limit") ?? "30", 10), 1), 100);
  const action = sp.get("action")?.trim() || null;
  const targetType = sp.get("targetType")?.trim() || null;

  const where: Prisma.AdminActionLogWhereInput = {};
  if (action) where.action = action;
  if (targetType) where.targetType = targetType;

  const rows = await prisma.adminActionLog.findMany({
    where,
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: limit + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    select: {
      id: true,
      action: true,
      targetType: true,
      targetId: true,
      summary: true,
      metadata: true,
      createdAt: true,
      actor: {
        select: { id: true, name: true, email: true },
      },
    },
  });

  const hasMore = rows.length > limit;
  const items = hasMore ? rows.slice(0, limit) : rows;
  const nextCursor = hasMore ? items[items.length - 1].id : null;

  return NextResponse.json({ items, nextCursor });
}
