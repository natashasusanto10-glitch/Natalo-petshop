/**
 * GET /api/cron/order-confirm-reminder — Vercel cron (daily)
 *
 * Nudge customer untuk tap "Sudah Diterima" di app sebelum sistem
 * otomatis selesai-kan order (cron auto-confirm-delivered jalan di
 * hari ke-7 setelah shipped).
 *
 * Timing: H-3 sebelum auto-confirm = hari ke-4 sejak shippedAt.
 * Rationale:
 *   - User dapat 3 hari window untuk respond manual
 *   - Manual confirm = data lebih accurate + (Tier 2 future) user dapat
 *     loyalty poin bonus
 *   - Hari ke-4 = realistic, paket biasanya udah sampai 2-5 hari
 *
 * Skip kalau:
 *   - Order self-pickup (gak transit SHIPPED)
 *   - Cancellation request PENDING (admin lagi review)
 *   - Sudah pernah di-remind (notifiedConfirmReminderAt != null)
 *
 * Schedule: "30 22 * * *" UTC = 05:30 WIB (sebelum auto-confirm cron
 * jam 04:00 WIB = berarti reminder JUSTRU sebelum cron auto-confirm
 * untuk hari yang sama — yang dapat reminder hari ini akan auto-confirm
 * 3 hari lagi, jadi gak konflik).
 *
 * CRON_SECRET auth. Batch limit 500.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { sendConfirmReminderPush } from "@/lib/push";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const REMINDER_DAY_OFFSET = 4; // H+4 dari shippedAt = H-3 dari auto-confirm
const BATCH_LIMIT = 500;

export async function GET(request: NextRequest) {
  const authHeader = request.headers.get("authorization");
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret && authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Window: orders yang shippedAt antara 4 dan 5 hari lalu (1 hari buffer
  // supaya kalau cron miss/delay 1 hari, masih ke-trigger). Exclude yang
  // sudah pernah dapat reminder via field notifiedConfirmReminderAt.
  const now = Date.now();
  const lower = new Date(now - (REMINDER_DAY_OFFSET + 1) * 24 * 60 * 60 * 1000);
  const upper = new Date(now - REMINDER_DAY_OFFSET * 24 * 60 * 60 * 1000);

  const candidates = await prisma.order.findMany({
    where: {
      status: "SHIPPED",
      orderType: { not: "SELF_PICKUP" },
      shippedAt: { gte: lower, lt: upper },
      cancellationRequestStatus: { not: "PENDING" },
      notifiedConfirmReminderAt: null,
      userId: { not: null }, // skip guest checkout (no push target)
    },
    select: {
      id: true,
      orderNumber: true,
      userId: true,
      shippedAt: true,
    },
    take: BATCH_LIMIT,
    orderBy: { shippedAt: "asc" },
  });

  if (candidates.length === 0) {
    return NextResponse.json({
      ok: true,
      processed: 0,
      message: "Tidak ada order yang perlu di-remind.",
    });
  }

  let succeeded = 0;
  let failed = 0;
  const errors: { orderId: string; error: string }[] = [];

  for (const order of candidates) {
    try {
      // Fire push via dedicated helper (APNs + FCM + Web + Announcement).
      await sendConfirmReminderPush({
        userId: order.userId!,
        orderId: order.id,
        orderNumber: order.orderNumber,
      });

      // Mark sent supaya tidak kirim ulang. Atomic AFTER push sukses.
      await prisma.order.update({
        where: { id: order.id },
        data: { notifiedConfirmReminderAt: new Date() },
      });

      succeeded += 1;
      console.log(
        `[confirm-reminder] ✓ order=${order.orderNumber} shippedAt=${order.shippedAt?.toISOString()}`,
      );
    } catch (err) {
      failed += 1;
      const message = err instanceof Error ? err.message : String(err);
      errors.push({ orderId: order.id, error: message });
      console.error(
        `[confirm-reminder] ✗ order=${order.orderNumber} error=${message}`,
      );
    }
  }

  return NextResponse.json({
    ok: true,
    processed: candidates.length,
    succeeded,
    failed,
    errors: errors.slice(0, 20),
  });
}
