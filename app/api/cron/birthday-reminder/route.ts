/**
 * GET /api/cron/birthday-reminder — Vercel cron (daily)
 *
 * H-1 teaser push "Besok ulang tahunmu!" untuk build anticipation
 * sebelum voucher di-issue cron berikutnya (besok pagi).
 *
 * Pattern Shopee/Tokopedia: dengan H-1 teaser, user buka app esok hari
 * dengan ekspektasi → langsung claim voucher → conversion lebih tinggi.
 *
 * Anti-spam: User.lastBirthdayTeaserYear di-set setelah push sukses.
 * Cron re-run dalam hari yang sama akan skip user yang sudah ke-flag.
 *
 * Schedule: "0 12 * * *" UTC = 19:00 WIB (waktu evening, user lagi
 * relax di rumah, lebih engagement-friendly daripada pagi).
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { sendPushToUser } from "@/lib/push";
import { sendApnsToUser } from "@/lib/apns";
import { sendFcmToUser } from "@/lib/fcm";
import type { PushPayload } from "@/lib/push";
import { findTomorrowBirthdayUsers } from "@/lib/birthday-voucher";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const BATCH_LIMIT = 500;

export async function GET(request: NextRequest) {
  const authHeader = request.headers.get("authorization");
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret && authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const now = new Date();
  const candidates = (await findTomorrowBirthdayUsers(now)).slice(0, BATCH_LIMIT);
  const currentYear = now.getUTCFullYear();

  if (candidates.length === 0) {
    return NextResponse.json({
      ok: true,
      processed: 0,
      message: "Tidak ada user ulang tahun besok yang perlu di-teaser.",
    });
  }

  let succeeded = 0;
  let failed = 0;

  for (const u of candidates) {
    // Defensive double-check race condition.
    if (u.lastBirthdayTeaserYear === currentYear) continue;

    const firstName = (u.name.split(" ")[0] || "").trim() || "Sahabat";
    const payload: PushPayload = {
      title: `🎂 Besok ulang tahunmu, ${firstName}!`,
      body: "Kami punya hadiah special buat kamu. Buka app besok pagi ya!",
      url: "/member/vouchers",
      tag: `birthday-teaser-${currentYear}-${u.id}`,
      category: "voucher",
      data: {
        type: "birthday_teaser",
        userId: u.id,
        year: String(currentYear),
      },
    };

    try {
      // Fanout ke 3 channel + announcement. Push send first, then
      // mark teaser year (atomic-ish — kalau push fail, retry next run).
      await Promise.all([
        sendPushToUser(u.id, payload),
        sendApnsToUser(u.id, payload),
        sendFcmToUser(u.id, payload),
        prisma.announcement
          .create({
            data: {
              title: payload.title,
              body: payload.body,
              url: payload.url,
              segment: "all",
              type: "info",
              ctaLabel: "Lihat Vouchers",
              publishedAt: new Date(),
              targetUserId: u.id,
            },
          })
          .catch((err) => {
            console.warn("[birthday-reminder] announcement:", err);
          }),
      ]);
      await prisma.user.update({
        where: { id: u.id },
        data: { lastBirthdayTeaserYear: currentYear },
      });
      succeeded += 1;
    } catch (err) {
      failed += 1;
      console.error("[birthday-reminder] dispatch failed:", {
        userId: u.id,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  return NextResponse.json({
    ok: true,
    processed: candidates.length,
    succeeded,
    failed,
  });
}
