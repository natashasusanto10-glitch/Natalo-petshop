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
import { checkLimit, getClientIp, getSearchLogLimiter } from "@/lib/rate-limit";
import {
  isSearchKeywordAllowed,
  normalizeSearchKeyword,
} from "@/lib/search-trending";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => null);
    const keyword = normalizeSearchKeyword(body?.keyword);

    if (!isSearchKeywordAllowed(keyword)) {
      return NextResponse.json(
        { ok: false, error: "Invalid keyword" },
        { status: 400 }
      );
    }

    const session = await getSession("CUSTOMER").catch(() => null);
    const clientKey = session?.sub ?? getClientIp(request.headers);
    const gate = await checkLimit(getSearchLogLimiter(), `search:${clientKey}`);
    if (!gate.ok) {
      return NextResponse.json(
        { ok: false, rateLimited: true },
        {
          status: 429,
          headers: { "Retry-After": String(gate.retryAfter) },
        }
      );
    }

    // One signed-in shopper repeating the same query should not manufacture a
    // trend. Anonymous traffic is still protected by the IP rate limit.
    if (session?.sub) {
      const duplicate = await prisma.searchLog.findFirst({
        where: {
          userId: session.sub,
          keyword,
          createdAt: { gte: new Date(Date.now() - 5 * 60 * 1000) },
        },
        select: { id: true },
      });
      if (duplicate) {
        return NextResponse.json({ ok: true, deduplicated: true });
      }
    }

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
