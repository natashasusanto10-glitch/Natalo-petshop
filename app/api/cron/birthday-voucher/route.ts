/**
 * GET /api/cron/birthday-voucher — daily 09:00 WIB
 *
 * Auto-issue voucher ulang tahun ke user yang berulang tahun hari ini.
 * Skip user yang sudah dapat voucher tahun ini (User.birthdayVoucherYear
 * === currentYear).
 *
 * Schedule: "0 2 * * *" UTC = 09:00 WIB pagi (waktu user buka HP).
 *
 * Auth: CRON_SECRET header check (same pattern as other crons).
 *
 * Lihat lib/birthday-voucher.ts untuk core logic.
 */
import { NextRequest, NextResponse } from "next/server";
import { runBirthdayVoucherJob } from "@/lib/birthday-voucher";

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
    const result = await runBirthdayVoucherJob(new Date());
    const elapsedMs = Date.now() - startedAt;
    console.log("[birthday-voucher] cron complete", {
      elapsedMs,
      candidates: result.candidates,
      issued: result.issued,
      skipped: result.skipped,
      errors: result.errors,
    });
    return NextResponse.json({
      ok: true,
      elapsedMs,
      result,
    });
  } catch (err) {
    console.error("[birthday-voucher] cron failed:", err);
    return NextResponse.json(
      { error: "Cron failed", message: String(err) },
      { status: 500 },
    );
  }
}
