/**
 * GET /api/cron/loyalty-points-reminder — Vercel cron (weekly)
 *
 * Reminder push untuk user yang punya poin loyalty cukup buat ditukar
 * jadi voucher TAPI belum tukar-tukar. Goal: boost redeem rate +
 * dorong user buka app & belanja (voucher punya minimum order).
 *
 * BUKAN notif "poin masuk" (itu redundant dgn push PAID + snackbar review).
 * Ini reminder berkala "kamu punya N poin, tukar yuk".
 *
 * Target:
 *   - Total poin (sum CustomerPoint) >= tier terendah (20 poin → Rp10k)
 *   - Belum di-reminder dalam 14 hari terakhir (anti-spam, keyed by
 *     Announcement eventType "loyalty_redeem_reminder" + targetUserId)
 *
 * Schedule: weekly (Senin 10:00 WIB). Lihat vercel.json crons.
 * Safety: CRON_SECRET, batch limit, per-user try/catch.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { sendApnsToUser } from "@/lib/apns";
import { sendFcmToUser } from "@/lib/fcm";
import { sendPushToUser, type PushPayload } from "@/lib/push";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

// Tier voucher tukar poin (mirror app/api/member/claim-voucher TIERS).
// Dipakai untuk tentukan reward terbaik yang user bisa klaim → pesan
// notif lebih menarik ("tukar jadi voucher Rp40rb").
const TIERS = [
  { points: 20, discountAmount: 10000 },
  { points: 50, discountAmount: 25000 },
  { points: 75, discountAmount: 40000 },
  { points: 100, discountAmount: 60000 },
  { points: 200, discountAmount: 150000 },
] as const;
const MIN_POINTS = TIERS[0].points;
const REMINDER_COOLDOWN_DAYS = 14;
const BATCH_LIMIT = 300;

function bestReward(points: number): number {
  let reward = 0;
  for (const t of TIERS) {
    if (points >= t.points) reward = t.discountAmount;
  }
  return reward;
}

export async function GET(request: NextRequest) {
  const authHeader = request.headers.get("authorization");
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret && authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // 1. Sum poin per user. CustomerPoint = ledger (positif earn, negatif
  //    claim) → groupBy sum = saldo poin sekarang.
  const balances = await prisma.customerPoint.groupBy({
    by: ["userId"],
    _sum: { points: true },
    having: { points: { _sum: { gte: MIN_POINTS } } },
  });

  if (balances.length === 0) {
    return NextResponse.json({ ok: true, processed: 0, message: "Tidak ada." });
  }

  // 2. Filter user yang sudah di-reminder dalam cooldown → skip.
  const cooldownStart = new Date(
    Date.now() - REMINDER_COOLDOWN_DAYS * 24 * 60 * 60 * 1000,
  );
  const userIds = balances.map((b) => b.userId);
  const recentReminders = await prisma.announcement.findMany({
    where: {
      eventType: "loyalty_redeem_reminder",
      targetUserId: { in: userIds },
      createdAt: { gte: cooldownStart },
    },
    select: { targetUserId: true },
  });
  const remindedRecently = new Set(
    recentReminders.map((r) => r.targetUserId).filter(Boolean) as string[],
  );

  const candidates = balances
    .filter((b) => !remindedRecently.has(b.userId))
    .slice(0, BATCH_LIMIT);

  if (candidates.length === 0) {
    return NextResponse.json({
      ok: true,
      processed: 0,
      message: "Semua sudah di-reminder dalam 14 hari terakhir.",
    });
  }

  const url = "/member/loyalty";
  let succeeded = 0;
  let failed = 0;

  for (const b of candidates) {
    const points = b._sum.points ?? 0;
    const reward = bestReward(points);
    if (reward <= 0) continue;

    const title = "Poin kamu siap ditukar 🎁";
    const body = `Kamu punya ${points} poin di Natalo Petshop — cukup buat voucher diskon hingga Rp${reward.toLocaleString(
      "id-ID",
    )}. Tukar sekarang sebelum lupa!`;

    const payload: PushPayload = {
      title,
      body,
      url,
      tag: `loyalty-redeem-${b.userId}`,
      data: {
        source: "loyalty",
        type: "loyalty_redeem_reminder",
        points: String(points),
        category: "loyalty_points",
        url,
      },
    };

    try {
      await Promise.allSettled([
        sendPushToUser(b.userId, payload),
        sendApnsToUser(b.userId, payload),
        sendFcmToUser(b.userId, payload),
        prisma.announcement.create({
          data: {
            title,
            body,
            url,
            segment: "all",
            type: "loyalty",
            source: "loyalty",
            eventType: "loyalty_redeem_reminder",
            ctaLabel: "Tukar Poin",
            publishedAt: new Date(),
            targetUserId: b.userId,
          },
        }),
      ]);
      succeeded += 1;
    } catch (err) {
      failed += 1;
      console.error(
        `[loyalty-reminder] gagal user=${b.userId}:`,
        err instanceof Error ? err.message : String(err),
      );
    }
  }

  return NextResponse.json({
    ok: true,
    processed: candidates.length,
    succeeded,
    failed,
    minPoints: MIN_POINTS,
    cooldownDays: REMINDER_COOLDOWN_DAYS,
  });
}
