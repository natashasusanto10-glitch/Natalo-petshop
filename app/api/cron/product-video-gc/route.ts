/**
 * GET /api/cron/product-video-gc
 *
 * Sapu orphan Bunny library produk. Auth via CRON_SECRET (Vercel Cron).
 */

import { NextRequest, NextResponse } from "next/server";
import { sweepProductVideoOrphans } from "@/lib/product/product-video-gc";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

function isAuthorized(request: NextRequest): boolean {
  const expected = process.env.CRON_SECRET;
  if (!expected) return false;
  return (request.headers.get("authorization") ?? "") === `Bearer ${expected}`;
}

export async function GET(request: NextRequest) {
  if (!isAuthorized(request)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const summary = await sweepProductVideoOrphans({ dryRun: false });
  return NextResponse.json({ ok: true, product: summary });
}
