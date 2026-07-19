/**
 * GET /api/cron/birthday-voucher-reminder — Vercel cron (daily)
 *
 * H+3 reminder push untuk voucher ulang tahun yang belum dipakai.
 * Goal: boost redeem rate — voucher issued tapi tidak dipakai = waste.
 * Push reminder kasih nudge supaya user inget pakai.
 *
 * Target voucher:
 *   - code prefix "BDAY-" (birthday voucher saja, bukan voucher lain)
 *   - userId != null (personal voucher)
 *   - usedCount = 0 (belum pernah dipakai)
 *   - createdAt antara 3 dan 4 hari lalu (1 day window untuk safety)
 *   - expiresAt > now (masih valid)
 *
 * Anti-spam: pakai time window only. Risk duplikat kecil (cron daily +
 * 1 day window = max 1 push per voucher). Tidak butuh schema field
 * tambahan untuk track.
 *
 * Schedule: "30 12 * * *" UTC = 19:30 WIB (after birthday-reminder cron).
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { sendPushToUser } from "@/lib/push";
import { sendFcmToUser } from "@/lib/fcm";
import type { PushPayload } from "@/lib/push";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const REMINDER_DAY_OFFSET = 3; // H+3 sejak voucher di-issue
const BATCH_LIMIT = 500;

function formatRupiahShort(n: number): string {
  if (n >= 1000) {
    const k = n / 1000;
    const fixed = k >= 10 ? k.toFixed(0) : k.toFixed(1);
    return `Rp${fixed.replace(".", ",").replace(",0", "")}rb`;
  }
  return `Rp${n.toLocaleString("id-ID")}`;
}

function formatExpiry(date: Date): string {
  const months = [
    "Jan", "Feb", "Mar", "Apr", "Mei", "Jun",
    "Jul", "Agt", "Sep", "Okt", "Nov", "Des",
  ];
  return `${date.getDate()} ${months[date.getMonth()]}`;
}

export async function GET(request: NextRequest) {
  const authHeader = request.headers.get("authorization");
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret && authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const now = Date.now();
  const lower = new Date(now - (REMINDER_DAY_OFFSET + 1) * 24 * 60 * 60 * 1000);
  const upper = new Date(now - REMINDER_DAY_OFFSET * 24 * 60 * 60 * 1000);

  const candidates = await prisma.voucher.findMany({
    where: {
      code: { startsWith: "BDAY-" },
      userId: { not: null },
      usedCount: 0,
      isActive: true,
      createdAt: { gte: lower, lt: upper },
      expiresAt: { gt: new Date() },
    },
    select: {
      id: true,
      code: true,
      userId: true,
      discountAmount: true,
      expiresAt: true,
    },
    take: BATCH_LIMIT,
  });

  if (candidates.length === 0) {
    return NextResponse.json({
      ok: true,
      processed: 0,
      message: "Tidak ada voucher H+3 yang perlu di-remind.",
    });
  }

  let succeeded = 0;
  let failed = 0;

  for (const voucher of candidates) {
    if (!voucher.userId) continue; // type guard (already filtered above)

    const amount = formatRupiahShort(voucher.discountAmount ?? 0);
    const expiry = formatExpiry(voucher.expiresAt!);
    const payload: PushPayload = {
      title: `🎁 Voucher ulang tahun ${amount} belum dipakai!`,
      body: `Berlaku sampai ${expiry}. Tap untuk lihat & pakai sekarang.`,
      url: "/member/vouchers",
      tag: `birthday-voucher-reminder-${voucher.id}`,
      category: "voucher",
      // Voucher ultah = toggle "Poin Loyalty" (lihat lib/birthday-voucher.ts).
      prefCategory: "loyalty_points",
      data: {
        type: "birthday_voucher_reminder",
        voucherCode: voucher.code,
      },
    };

    try {
      // 2 channel (web + FCM) — sendApnsToUser dihapus, lihat komentar di
      // lib/push.ts sendOrderStatusPush utk alasan (dobel notif iOS).
      await Promise.all([
        sendPushToUser(voucher.userId, payload),
        sendFcmToUser(voucher.userId, payload),
        prisma.announcement
          .create({
            data: {
              title: payload.title,
              body: payload.body,
              url: payload.url,
              segment: "all",
              type: "info",
              ctaLabel: "Lihat Voucher",
              publishedAt: new Date(),
              targetUserId: voucher.userId,
            },
          })
          .catch((err) => {
            console.warn("[birthday-voucher-reminder] announcement:", err);
          }),
      ]);
      succeeded += 1;
    } catch (err) {
      failed += 1;
      console.error("[birthday-voucher-reminder] dispatch failed:", {
        voucherId: voucher.id,
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
