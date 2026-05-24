/**
 * GET /api/cron/voucher-abuse-detect — Vercel cron daily
 *
 * Run 4 detection rules untuk flag suspicious user pattern:
 *   - BURST_VOUCHER_CLAIM (claim 3+ voucher dalam 1 jam)
 *   - GMAIL_ALIAS_DUPLICATE (multi-account via gmail dot/plus alias)
 *   - DUPLICATE_SHIPPING_ADDRESS (3+ user kirim ke alamat sama)
 *   - NEW_ACCOUNT_INSTANT_CLAIM (register + claim < 5 menit gap)
 *
 * Flagged user di-record ke AbuseFlag table dengan status=OPEN.
 * Admin review via /admin/abuse-flags untuk decide block / dismiss /
 * monitor.
 *
 * Idempotent — re-run safe, skip create kalau OPEN flag existing
 * untuk user+rule combo sama.
 *
 * Schedule: daily @ 03:00 WIB (lihat vercel.json crons).
 */
import { NextRequest, NextResponse } from "next/server";
import { runAllAbuseDetection } from "@/lib/abuse-detection";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(request: NextRequest) {
  const authHeader = request.headers.get("authorization");
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret && authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const startedAt = Date.now();
  try {
    const result = await runAllAbuseDetection();
    const elapsedMs = Date.now() - startedAt;
    console.log("[abuse-detection] cron complete", {
      elapsedMs,
      result,
    });
    return NextResponse.json({
      ok: true,
      elapsedMs,
      flagsCreated: result,
    });
  } catch (err) {
    console.error("[abuse-detection] cron failed:", err);
    return NextResponse.json(
      { error: "Detection failed", message: String(err) },
      { status: 500 },
    );
  }
}
