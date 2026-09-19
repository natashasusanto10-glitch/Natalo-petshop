/**
 * GET /api/cron/product-video-gc
 *
 * Sapu orphan Bunny library produk. Auth via CRON_SECRET (Vercel Cron).
 */

import { NextRequest, NextResponse } from "next/server";
import { assertCronAuth } from "@/lib/cron-auth";
import { sweepProductVideoOrphans } from "@/lib/product/product-video-gc";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(request: NextRequest) {
  const unauthorized = assertCronAuth(request);
  if (unauthorized) return unauthorized;
  const summary = await sweepProductVideoOrphans({ dryRun: false });
  return NextResponse.json({ ok: true, product: summary });
}
