/**
 * POST /api/orders/[orderNumber]/cancel
 *
 * User-initiated order cancellation. DUA MODE berdasarkan paymentStatus:
 *
 * 1) INSTANT (paymentStatus !== "PAID"):
 *    User belum bayar / admin belum konfirmasi bayar → cancel langsung
 *    diterima tanpa approval admin. Stock/voucher/points rollback dilakukan
 *    saat itu juga. Tidak ada refund karena tidak ada duit masuk.
 *    Response: { ok: true, mode: "instant", status: "CANCELLED" }
 *
 * 2) REQUESTED (paymentStatus === "PAID"):
 *    User sudah bayar dan admin sudah konfirmasi → cancel TIDAK langsung
 *    diterapkan. Sebagai gantinya, request masuk antrian approval admin:
 *      - order.cancellationRequestStatus = "PENDING"
 *      - order.cancellationReason = reason (kalau ada)
 *      - order.cancellationRequestedAt = now
 *      - order.status TIDAK berubah (tetap PAID/PROCESSING)
 *    Admin lihat banner di order detail → klik [Setujui & Refund] atau
 *    [Tolak]. Approve jalanin flow markAsCancelled (auto-refund). Reject
 *    set field cancellationRejectReason.
 *    Response: { ok: true, mode: "requested", awaitingApproval: true }
 *
 * Status guard (sama untuk dua mode):
 *   - Allowed: PENDING, PAID, PROCESSING
 *   - Disallowed: READY_FOR_PICKUP, SHIPPED, DELIVERED, CANCELLED, REFUNDED
 *
 * Idempotency:
 *   - Kalau sudah ada pending request, return 409 dengan pesan "sudah
 *     diajukan, tunggu konfirmasi admin" — bukan duplicate.
 *
 * Body opsional: `{ reason?: string }` — alasan user, di-store di
 * cancellationReason field untuk request mode, di-log untuk instant mode.
 */

import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { assertSameOrigin } from "@/lib/csrf";
import { creditWallet } from "@/lib/refund-wallet";
import { sendRefundIssuedPush } from "@/lib/push-refund";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> }
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json(
      { error: "Silakan login member terlebih dahulu." },
      { status: 401 }
    );
  }

  const { orderNumber } = await params;
  if (!orderNumber || orderNumber.trim().length === 0) {
    return NextResponse.json(
      { error: "Order number tidak valid." },
      { status: 400 }
    );
  }

  const body = await request.json().catch(() => ({}));
  const reason = String(body.reason ?? "").trim().slice(0, 500);

  try {
    const order = await prisma.order.findUnique({
      where: { orderNumber },
      include: { items: true },
      // userId terikat dengan customer ownership — check di handler logic
    });

    if (!order) {
      return NextResponse.json(
        { error: "Pesanan tidak ditemukan." },
        { status: 404 }
      );
    }

    // Customer ownership check — order.userId harus match session.sub.
    // Anti-bypass: user A tidak boleh cancel order user B walau punya
    // nomor order-nya.
    if (order.userId !== session.sub) {
      return NextResponse.json(
        { error: "Pesanan ini bukan milikmu." },
        { status: 403 }
      );
    }

    // Status guard: user boleh cancel "sebelum paket dikirim".
    // Allowed: PENDING, PAID, PROCESSING.
    // Disallowed: READY_FOR_PICKUP (paket sudah disiapkan di toko, harus
    // datang ambil atau request void manual), SHIPPED (paket di kurir),
    // DELIVERED (sudah selesai), CANCELLED/REFUNDED (terminal).
    const CANCELLABLE_BY_USER = ["PENDING", "PAID", "PROCESSING"] as const;
    if (!CANCELLABLE_BY_USER.includes(order.status as typeof CANCELLABLE_BY_USER[number])) {
      const reasonByStatus: Record<string, string> = {
        READY_FOR_PICKUP:
          "Pesanan sudah disiapkan untuk pickup — hubungi admin via WhatsApp untuk batalkan.",
        SHIPPED:
          "Paket sudah dikirim ke kurir — tidak bisa dibatalkan. Tunggu paket sampai lalu proses retur jika ada masalah.",
        DELIVERED:
          "Pesanan sudah selesai. Untuk masalah barang, ajukan retur via fitur komplain.",
        CANCELLED: "Pesanan sudah dibatalkan sebelumnya.",
        REFUNDED: "Pesanan sudah ditandai refunded.",
      };
      return NextResponse.json(
        {
          error:
            reasonByStatus[order.status] ??
            "Pesanan tidak bisa dibatalkan karena status saat ini.",
        },
        { status: 409 }
      );
    }

    // ── MODE 2: Request mode (paymentStatus === PAID) ──────────────────
    // User sudah bayar dan admin sudah konfirmasi → tidak boleh cancel
    // langsung. Bikin pending request supaya admin bisa review.
    //
    // Idempotency: kalau sudah ada request PENDING, return info "sudah
    // diajukan" (bukan duplicate). Kalau status REJECTED sebelumnya, user
    // boleh submit ulang (overwrite jadi PENDING).
    if (order.paymentStatus === "PAID") {
      if (order.cancellationRequestStatus === "PENDING") {
        return NextResponse.json(
          {
            ok: true,
            mode: "requested",
            awaitingApproval: true,
            alreadyRequested: true,
            requestedAt: order.cancellationRequestedAt,
            message:
              "Permintaan pembatalan sudah diajukan sebelumnya. Tunggu konfirmasi admin.",
          },
          { status: 200 }
        );
      }

      await prisma.order.update({
        where: { id: order.id },
        data: {
          cancellationRequestStatus: "PENDING",
          cancellationReason: reason.length > 0 ? reason : null,
          cancellationRequestedAt: new Date(),
          // Reset response fields kalau user submit ulang setelah reject.
          cancellationRespondedAt: null,
          cancellationRespondedByAdminId: null,
          cancellationRejectReason: null,
        },
      });

      console.log(
        `[order-cancel-request] order=${order.orderNumber} user=${session.sub} reason=${reason || "(none)"}`,
      );

      // Push notif ke admin — supaya admin tidak perlu polling, langsung
      // tahu ada cancel request masuk dan bisa respond cepat.
      void import("@/lib/push-admin").then(
        ({ sendAdminCancellationRequestPush }) => {
          sendAdminCancellationRequestPush({
            orderNumber: order.orderNumber,
            customerName: order.customerName,
            reason: reason || null,
          });
        },
      );

      return NextResponse.json({
        ok: true,
        mode: "requested",
        awaitingApproval: true,
        requestedAt: new Date().toISOString(),
        message:
          "Permintaan pembatalan dikirim. Menunggu konfirmasi admin.",
      });
    }

    // ── MODE 1: Instant cancel (paymentStatus !== PAID) ────────────────
    // User belum bayar → cancel langsung. Tidak ada refund karena tidak
    // ada duit yang masuk.
    const variantProductIdsToSync = new Set<string>();
    const nonVariantProductIdsToSync = new Set<string>();
    // Tracking nominal refund untuk response + push notif setelah commit.
    // Untuk instant mode kedua tetap 0 (tidak ada duit yang masuk +
    // tidak boleh pakai saldo untuk order yang belum konfirm bayar).
    let reversedSaldo = 0;
    let autoRefundedAmount = 0;

    await prisma.$transaction(async (tx) => {
      // 1. Restore stock — increment back product + variant counts.
      for (const item of order.items) {
        if (item.variantId) {
          await tx.productVariant.updateMany({
            where: { id: item.variantId },
            data: { stock: { increment: item.quantity } },
          });
          variantProductIdsToSync.add(item.productId);
        } else {
          await tx.product.updateMany({
            where: { id: item.productId },
            data: { stock: { increment: item.quantity } },
          });
          nonVariantProductIdsToSync.add(item.productId);
        }
      }

      // Recompute product.stock dari sum variants untuk product yang
      // pakai variant (mirror admin cancel logic).
      for (const pid of variantProductIdsToSync) {
        const agg = await tx.productVariant.aggregate({
          where: { productId: pid, deletedAt: null, isActive: true },
          _sum: { stock: true },
        });
        await tx.product.update({
          where: { id: pid },
          data: { stock: agg._sum.stock ?? 0 },
        });
      }

      // 2. Rollback voucher usage — kalau order pakai voucher, decrement
      // usedCount supaya quota tidak ke-burn.
      const voucherCodes = [
        ...new Set(
          [
            order.voucherCode,
            order.productVoucherCode,
            order.shippingVoucherCode,
            order.loyaltyVoucherCode,
            order.manualVoucherCode,
          ].filter((code): code is string => Boolean(code))
        ),
      ];
      if (voucherCodes.length > 0) {
        await tx.voucher.updateMany({
          where: { code: { in: voucherCodes }, usedCount: { gt: 0 } },
          data: { usedCount: { decrement: 1 } },
        });
      }

      // 3. Hapus CustomerPoint yang granted dari order ini — customer
      // tidak boleh keep points untuk order yang cancel.
      await tx.customerPoint.deleteMany({
        where: { source: `ORDER:${order.orderNumber}` },
      });

      // 4. Reversal saldo refund — kalau order pakai saldo, balikin ke
      // wallet. Atomic dengan order update supaya tidak hilang.
      if (order.refundBalanceUsed > 0 && order.userId) {
        await creditWallet(
          {
            userId: order.userId,
            amount: order.refundBalanceUsed,
            sourceOrderId: order.id,
            note: `Pembatalan pesanan ${order.orderNumber}`,
            type: "REVERSAL",
          },
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          tx as any,
        );
        reversedSaldo = order.refundBalanceUsed;
      }

      // 5. Auto-refund nominal yang user bayar (non-saldo).
      //
      // Aturan dari spec owner:
      //   - paymentStatus === "PAID" → ada duit yang masuk → auto-refund
      //     full sisa ke Saldo Refund user
      //   - paymentStatus !== "PAID" (UNPAID/PENDING/FAILED/EXPIRED) →
      //     admin belum konfirmasi bayar / user belum bayar → no refund
      //
      // Logic mirror dengan admin markAsCancelled supaya admin/user flow
      // konsisten. Sum existing CREDITED refund dulu supaya kalau ada
      // partial refund sebelumnya (mis. OOS), cancel hanya kredit sisa.
      if (order.paymentStatus === "PAID" && order.userId) {
        const existing = await tx.refundCase.aggregate({
          where: { orderId: order.id, status: "CREDITED" },
          _sum: { amount: true },
        });
        const alreadyRefunded = existing._sum.amount ?? 0;
        const amountToRefund = order.total - alreadyRefunded;

        if (amountToRefund > 0) {
          const refundCase = await tx.refundCase.create({
            data: {
              orderId: order.id,
              userId: order.userId,
              reason: "ORDER_CANCELLED",
              amount: amountToRefund,
              destination: "REFUND_BALANCE",
              status: "PENDING",
              adminNote: `Pembatalan oleh customer (order ${order.orderNumber})`,
            },
          });

          const credit = await creditWallet(
            {
              userId: order.userId,
              amount: amountToRefund,
              sourceOrderId: order.id,
              sourceRefundCaseId: refundCase.id,
              note: `Auto-refund pembatalan order ${order.orderNumber}`,
              type: "CREDIT",
            },
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            tx as any,
          );

          await tx.refundCase.update({
            where: { id: refundCase.id },
            data: {
              status: "CREDITED",
              approvedAt: new Date(),
              creditedAt: new Date(),
              ledgerEntryId: credit.ledgerEntryId,
            },
          });

          autoRefundedAmount = amountToRefund;
        }
      }

      // 6. Update order ke CANCELLED. Reason di-log saja untuk audit
      // (Order.cancelReason field belum ada di schema; bisa di-add via
      // migration belakangan tanpa break flow).
      await tx.order.update({
        where: { id: order.id },
        data: { status: "CANCELLED" },
      });
      if (reason.length > 0) {
        console.log(
          `[order-cancel] order=${order.orderNumber} reason=${reason}`,
        );
      }
    });

    // Push notif user — auto-refund jadi instant feedback. Fire-and-forget.
    if (autoRefundedAmount > 0 && order.userId) {
      void sendRefundIssuedPush({
        userId: order.userId,
        caseId: order.id,
        amount: autoRefundedAmount,
        reason: "ORDER_CANCELLED",
        itemName: null,
        adminNote: `Pembatalan order ${order.orderNumber}`,
      });
    }

    // Search index sync (best-effort, non-blocking).
    const allIdsToSync = [
      ...variantProductIdsToSync,
      ...nonVariantProductIdsToSync,
    ];
    if (allIdsToSync.length > 0) {
      try {
        const { syncProduct } = await import("@/lib/search");
        await Promise.all(allIdsToSync.map((pid) => syncProduct(pid)));
      } catch {
        // Search sync fail tidak block cancel — sudah commit.
      }
    }

    return NextResponse.json({
      ok: true,
      mode: "instant",
      orderNumber: order.orderNumber,
      status: "CANCELLED",
      // Nominal yang otomatis kredit ke Saldo Refund. Untuk instant mode
      // selalu 0 (paymentStatus belum PAID di branch ini).
      autoRefundedAmount,
      // Saldo refund yang DIPAKAI bayar dan otomatis dikembalikan ke wallet
      // (terpisah dari autoRefundedAmount). Bisa > 0 kalau user pakai saldo
      // untuk order yang manual-bayar dan belum dikonfirmasi admin.
      reversedSaldo,
    });
  } catch (error) {
    console.error("[order-cancel] error:", error);
    return NextResponse.json(
      { error: "Pembatalan pesanan sedang bermasalah. Coba lagi sebentar." },
      { status: 500 }
    );
  }
}
