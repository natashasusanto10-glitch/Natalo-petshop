/**
 * GET /api/cron/auto-cancel-unpaid-manual — Vercel cron (daily)
 *
 * Auto-cancel order pembayaran MANUAL (transfer bank) yang tidak
 * dibayar-bayar dalam grace period. Tanpa cron ini, order MANUAL hold
 * stok selamanya (paymentStatus PENDING + status PENDING) → attacker
 * bisa spam order besar untuk kunci inventory (inventory-DoS). Standard
 * e-commerce ID (Tokopedia/Shopee) batas transfer ~1 hari.
 *
 * Criteria order yang di-auto-cancel:
 *   - paymentProvider === "MANUAL"
 *   - paymentStatus === "PENDING" (belum dikonfirmasi admin / belum bayar)
 *   - status === "PENDING" (belum diproses admin jadi PAID/PROCESSING)
 *   - createdAt < now - AUTO_CANCEL_MANUAL_HOURS (default 24 jam)
 *   - cancellationRequestStatus !== "PENDING" (jangan tabrak flow request
 *     batal yang lagi nunggu admin — walau jarang untuk order belum bayar)
 *
 * Behavior per order match (mirror MODE 1 instant-cancel di
 * app/api/orders/[orderNumber]/cancel/route.ts):
 *   - Restore stock (product + variant, recompute parent stock)
 *   - Rollback voucher usedCount
 *   - Hapus CustomerPoint granted (source ORDER:<num>)
 *   - Reverse saldo refund yang dipakai (kalau ada) → wallet
 *   - Set status CANCELLED
 *   - TIDAK ada auto-refund (paymentStatus != PAID = belum ada duit masuk)
 *
 * Schedule: daily jam 03:30 WIB (off-peak). Lihat vercel.json crons.
 *
 * Idempotent: order yang sudah CANCELLED tidak match lagi di run
 * berikutnya (status bukan PENDING). Safe untuk multiple invocations.
 *
 * Safety: CRON_SECRET header, batch limit 200, per-order try/catch.
 */
import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { recordOrderStatusEvent } from "@/lib/order-transitions";
import { creditWallet } from "@/lib/refund-wallet";
import { sendOrderStatusPush } from "@/lib/push";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const DEFAULT_AUTO_CANCEL_HOURS = 24;
const BATCH_LIMIT = 200;

export async function GET(request: NextRequest) {
  const authHeader = request.headers.get("authorization");
  const cronSecret = process.env.CRON_SECRET;
  if (cronSecret && authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const hoursEnv = process.env.AUTO_CANCEL_MANUAL_HOURS;
  const hours = hoursEnv ? parseInt(hoursEnv, 10) : DEFAULT_AUTO_CANCEL_HOURS;
  const validHours =
    Number.isFinite(hours) && hours > 0 ? hours : DEFAULT_AUTO_CANCEL_HOURS;
  const threshold = new Date(Date.now() - validHours * 60 * 60 * 1000);

  const candidates = await prisma.order.findMany({
    where: {
      paymentProvider: "MANUAL",
      paymentStatus: "PENDING",
      status: "PENDING",
      createdAt: { lt: threshold },
      cancellationRequestStatus: { not: "PENDING" },
      // CRITICAL: JANGAN cancel order yang user sudah upload bukti bayar.
      // Upload bukti tidak mengubah paymentStatus (tetap PENDING) — cuma
      // set paymentProofUrl. Order ini sedang "menunggu verifikasi admin",
      // bukan "user belum bayar". Tanpa guard ini, customer yg sudah
      // transfer + upload bukti bisa ke-cancel sistem kalau admin telat
      // verifikasi > threshold. Order ber-bukti = tanggung jawab admin
      // untuk verifikasi/tolak manual, bukan auto-cancel.
      paymentProofUrl: null,
    },
    select: {
      id: true,
      orderNumber: true,
      userId: true,
      total: true,
      refundBalanceUsed: true,
      voucherCode: true,
      productVoucherCode: true,
      shippingVoucherCode: true,
      loyaltyVoucherCode: true,
      manualVoucherCode: true,
      items: {
        select: { productId: true, variantId: true, quantity: true },
      },
    },
    take: BATCH_LIMIT,
    orderBy: { createdAt: "asc" },
  });

  if (candidates.length === 0) {
    return NextResponse.json({
      ok: true,
      processed: 0,
      thresholdHours: validHours,
      message: "Tidak ada order MANUAL yang perlu auto-cancel.",
    });
  }

  let succeeded = 0;
  let failed = 0;
  const errors: { orderId: string; error: string }[] = [];

  for (const order of candidates) {
    try {
      await prisma.$transaction(async (tx) => {
        // 1. Restore stock.
        const variantProductIds = new Set<string>();
        for (const item of order.items) {
          if (item.variantId) {
            await tx.productVariant.updateMany({
              where: { id: item.variantId },
              data: { stock: { increment: item.quantity } },
            });
            variantProductIds.add(item.productId);
          } else {
            await tx.product.updateMany({
              where: { id: item.productId },
              data: { stock: { increment: item.quantity } },
            });
          }
        }
        for (const pid of variantProductIds) {
          const agg = await tx.productVariant.aggregate({
            where: { productId: pid, deletedAt: null, isActive: true },
            _sum: { stock: true },
          });
          await tx.product.update({
            where: { id: pid },
            data: { stock: agg._sum.stock ?? 0 },
          });
        }

        // 2. Rollback voucher usedCount.
        const voucherCodes = [
          ...new Set(
            [
              order.voucherCode,
              order.productVoucherCode,
              order.shippingVoucherCode,
              order.loyaltyVoucherCode,
              order.manualVoucherCode,
            ].filter((code): code is string => Boolean(code)),
          ),
        ];
        if (voucherCodes.length > 0) {
          await tx.voucher.updateMany({
            where: { code: { in: voucherCodes }, usedCount: { gt: 0 } },
            data: { usedCount: { decrement: 1 } },
          });
        }

        // 3. Hapus CustomerPoint granted dari order ini.
        await tx.customerPoint.deleteMany({
          where: { source: `ORDER:${order.orderNumber}` },
        });

        // 4. Reverse saldo refund yang dipakai (kalau ada).
        if (order.refundBalanceUsed > 0 && order.userId) {
          await creditWallet(
            {
              userId: order.userId,
              amount: order.refundBalanceUsed,
              sourceOrderId: order.id,
              note: `Auto-cancel order MANUAL tak dibayar ${order.orderNumber}`,
              type: "REVERSAL",
            },
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            tx as any,
          );
        }

        // 5. Set CANCELLED. TIDAK auto-refund (paymentStatus != PAID).
        await tx.order.update({
          where: { id: order.id },
          data: { status: "CANCELLED" },
        });
        await recordOrderStatusEvent(tx, order.id, "CANCELLED", {
          actorType: "CRON",
          actorId: "auto-cancel-unpaid-manual",
          idempotencyKey: `auto-cancel-unpaid-manual:${order.id}`,
        });
      });

      // WAJIB await — void promise bisa dibekukan Vercel begitu response
      // cron terkirim → push CANCELLED tidak pernah jalan. Error ditelan.
      await sendOrderStatusPush(
        order.id,
        order.orderNumber,
        "CANCELLED",
      ).catch(() => {});

      succeeded += 1;
      console.log(
        `[auto-cancel-manual] ✓ order=${order.orderNumber} (unpaid > ${validHours}h)`,
      );
    } catch (err) {
      failed += 1;
      const message = err instanceof Error ? err.message : String(err);
      errors.push({ orderId: order.id, error: message });
      console.error(
        `[auto-cancel-manual] ✗ order=${order.orderNumber} error=${message}`,
      );
    }
  }

  return NextResponse.json({
    ok: true,
    processed: candidates.length,
    succeeded,
    failed,
    thresholdHours: validHours,
    thresholdDate: threshold.toISOString(),
    errors: errors.slice(0, 20),
  });
}
