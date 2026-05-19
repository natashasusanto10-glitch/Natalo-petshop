/**
 * POST /api/orders/[orderNumber]/cancel
 *
 * User-initiated order cancellation. Berbeda dengan admin cancel
 * (app/admin/(protected)/orders/[id]/actions.ts:markAsCancelled),
 * customer hanya boleh cancel order:
 *   - yang dia OWN (matching session userId)
 *   - status PENDING dan paymentStatus belum PAID
 *
 * Setelah cancel sukses:
 *   - status → CANCELLED
 *   - Stock di-restore (product + variant)
 *   - Voucher usage di-rollback (decrement usedCount)
 *   - CustomerPoint yang granted dari order ini di-delete
 *
 * Body opsional: `{ reason?: string }` — saat ini di-log saja
 * (Order.cancelReason field belum ada di schema; bisa ditambah belakangan).
 */

import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { assertSameOrigin } from "@/lib/csrf";

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

    // Hanya order PENDING yang belum dibayar yang boleh di-cancel customer.
    // Kalau sudah PAID/PROCESSING/SHIPPED/dst — harus kontak admin
    // (mereka punya markAsCancelled action yang restore + refund manual).
    if (order.status !== "PENDING") {
      return NextResponse.json(
        {
          error:
            "Pesanan tidak bisa dibatalkan karena status sudah berubah. " +
            "Hubungi admin via WhatsApp untuk bantuan.",
        },
        { status: 409 }
      );
    }
    if (order.paymentStatus === "PAID") {
      return NextResponse.json(
        {
          error:
            "Pembayaran sudah diterima — hubungi admin untuk proses refund.",
        },
        { status: 409 }
      );
    }
    // Note: tidak perlu cek order.status === "CANCELLED" — sudah di-cover
    // oleh check `status !== "PENDING"` di atas.

    const variantProductIdsToSync = new Set<string>();
    const nonVariantProductIdsToSync = new Set<string>();

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

      // 4. Update order ke CANCELLED. Reason di-log saja untuk audit
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
      orderNumber: order.orderNumber,
      status: "CANCELLED",
    });
  } catch (error) {
    console.error("[order-cancel] error:", error);
    return NextResponse.json(
      { error: "Pembatalan pesanan sedang bermasalah. Coba lagi sebentar." },
      { status: 500 }
    );
  }
}
