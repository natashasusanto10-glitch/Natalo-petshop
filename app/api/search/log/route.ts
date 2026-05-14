/**
 * POST /api/search/log
 *
 * Append a search-keyword event. Used by the search overlay so the
 * "Pencarian populer" panel can rank keywords by 7-day frequency.
 *
 * Fire-and-forget from the client. Failure to log must never block the
 * actual search, so callers should not await this response on the
 * critical path.
 */

import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => null);
    const keyword = String(body?.keyword ?? "")
      .trim()
      .toLowerCase()
      .slice(0, 100);

    if (!keyword) {
      return NextResponse.json({ ok: false, error: "Empty keyword" }, { status: 400 });
    }

    const session = await getSession("CUSTOMER").catch(() => null);
    await prisma.searchLog.create({
      data: {
        keyword,
        userId: session?.sub ?? null,
      },
    });

    return NextResponse.json({ ok: true });
  } catch (error) {
    // Don't surface logging failures to the client — the search itself
    // must still go through.
    return NextResponse.json({ ok: false }, { status: 200 });
  }
}
