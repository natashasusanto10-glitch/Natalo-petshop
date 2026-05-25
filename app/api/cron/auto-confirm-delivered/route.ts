/**
 * GET /api/cron/auto-confirm-delivered — Vercel cron (daily)
 *
 * Auto-confirm pesanan yang sudah lama di status SHIPPED tapi user belum
 * pencet "Sudah Diterima" — implicitly anggap sudah sampai supaya:
 *   - Order tidak stuck SHIPPED selamanya
 *   - Window komplain/refund tutup setelah grace period
 *   - Metrics "Pesanan Selesai" akurat
 *
 * Criteria order yang di-auto-confirm:
 *   - status === "SHIPPED"
 *   - orderType !== "SELF_PICKUP" (self-pickup di-handle admin via scan
 *     di toko, bukan via cron)
 *   - shippedAt < now - AUTO_CONFIRM_DELAY (default 7 hari)
 *   - cancellationRequestStatus !== "PENDING" (kalau user lagi minta
 *     batal, jangan keburu auto-confirm — biarkan admin respond dulu)
 *
 * Behavior per order yang match:
 *   - transitionOrderStatus → DELIVERED
 *   - sendOrderStatusEmail "DELIVERED"
 *   - sendOrderStatusPush "DELIVERED"
 *
 * Schedule: daily jam 04:00 WIB (off-peak, hindari trafik retail).
 * Lihat vercel.json crons config.
 *
 * Idempotent: kalau cron re-run dalam hari yang sama, order yang sudah
 * di-confirm di run sebelumnya tidak akan match lagi (status sudah
 * DELIVERED, bukan SHIPPED). Safe untuk multiple invocations.
 *
 * Safety:
 *   - CRON_SECRET header verification
 *   - Batch limit 500 per run (defensive, normally far less)
 *   - Per-order try/catch supaya 1 failure tidak block sisa batch
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { transitionOrderStatus } from "@/lib/order-transitions";
import { sendOrderStatusEmail } from "@/lib/email-order";
import { sendOrderStatusPush } from "@/lib/push";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/**
 * Grace period sebelum auto-confirm. 7 hari = baseline yang masuk akal
 * untuk kurir Indonesia (JNE/JNT/SiCepat domestik biasa 2-5 hari, sisa
 * buffer untuk delay kurir / weekend / customer offline beberapa hari).
 *
 * Bisa di-tuning via env var `AUTO_CONFIRM_DAYS` kalau owner mau coba
 * value lain tanpa redeploy schema.
 */
const DEFAULT_AUTO_CONFIRM_DAYS = 7;
const BATCH_LIMIT = 500;

export async function GET(request: NextRequest) {
  // Vercel auto-inject CRON_SECRET. Public route tapi cuma Vercel infra
  // yang bisa set header ini.
  const authHeader = request.headers.get("authorization");
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret && authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const daysEnv = process.env.AUTO_CONFIRM_DAYS;
  const days = daysEnv ? parseInt(daysEnv, 10) : DEFAULT_AUTO_CONFIRM_DAYS;
  const validDays = Number.isFinite(days) && days > 0 ? days : DEFAULT_AUTO_CONFIRM_DAYS;
  const threshold = new Date(Date.now() - validDays * 24 * 60 * 60 * 1000);

  const candidates = await prisma.order.findMany({
    where: {
      status: "SHIPPED",
      orderType: { not: "SELF_PICKUP" },
      shippedAt: { lt: threshold },
      // Jangan auto-confirm kalau user lagi request batal — biar admin
      // respond dulu (Approve / Reject) supaya tidak conflict.
      cancellationRequestStatus: { not: "PENDING" },
    },
    select: {
      id: true,
      orderNumber: true,
      trackingToken: true,
      customerName: true,
      customerPhone: true,
      customerEmail: true,
      total: true,
      trackingNumber: true,
      courierCode: true,
      courierService: true,
      paymentUrl: true,
      shippedAt: true,
    },
    take: BATCH_LIMIT,
    orderBy: { shippedAt: "asc" }, // process yang paling lama dulu
  });

  if (candidates.length === 0) {
    return NextResponse.json({
      ok: true,
      processed: 0,
      thresholdDays: validDays,
      message: "Tidak ada order yang perlu auto-confirm.",
    });
  }

  let succeeded = 0;
  let failed = 0;
  const errors: { orderId: string; error: string }[] = [];

  for (const order of candidates) {
    try {
      await transitionOrderStatus(order.id, "DELIVERED");

      // Email + push notif — kasih tahu user kalau order otomatis
      // ditandai selesai. Push dipakai untuk user yang offline lama
      // (probably reason kenapa mereka tidak konfirmasi sendiri).
      const emailCtx = {
        orderNumber: order.orderNumber,
        trackingToken: order.trackingToken,
        customerName: order.customerName,
        customerPhone: order.customerPhone,
        customerEmail: order.customerEmail,
        total: order.total,
        trackingNumber: order.trackingNumber,
        courierCode: order.courierCode,
        courierService: order.courierService,
        paymentUrl: order.paymentUrl,
      };
      void sendOrderStatusEmail("DELIVERED", emailCtx).catch(() => {});
      void sendOrderStatusPush(order.id, order.orderNumber, "DELIVERED").catch(
        () => {},
      );

      succeeded += 1;
      console.log(
        `[auto-confirm] ✓ order=${order.orderNumber} shippedAt=${order.shippedAt?.toISOString()}`,
      );
    } catch (err) {
      failed += 1;
      const message = err instanceof Error ? err.message : String(err);
      errors.push({ orderId: order.id, error: message });
      console.error(
        `[auto-confirm] ✗ order=${order.orderNumber} error=${message}`,
      );
    }
  }

  return NextResponse.json({
    ok: true,
    processed: candidates.length,
    succeeded,
    failed,
    thresholdDays: validDays,
    thresholdDate: threshold.toISOString(),
    errors: errors.slice(0, 20), // cap to avoid huge response
  });
}
