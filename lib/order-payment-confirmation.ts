import { prisma } from "@/lib/prisma";
import { createBiteshipShipment } from "@/lib/biteship";
import { sendOrderStatusEmail } from "@/lib/email-order";
import { recordOrderStatusEvent } from "@/lib/order-transitions";
import { sendOrderStatusPush } from "@/lib/push";
import { SELF_PICKUP_METHOD } from "@/lib/self-pickup";

export class PaymentConfirmationConflict extends Error {}

export async function confirmOrderPayment(params: {
  orderId: string;
  actorId: string;
  expectedProofVersion?: number;
  allowAlreadyPaid?: boolean;
}) {
  const result = await prisma.$transaction(async (tx) => {
    const current = await tx.order.findUnique({
      where: { id: params.orderId },
      select: {
        id: true,
        status: true,
        paymentStatus: true,
        paymentProofStatus: true,
        paymentProofVersion: true,
        paymentProofUrl: true,
        orderType: true,
        orderNumber: true,
        total: true,
      },
    });
    if (!current) throw new Error("Order tidak ditemukan.");
    if (current.status === "CANCELLED" || current.status === "REFUNDED") {
      throw new PaymentConfirmationConflict("Order sudah dibatalkan atau di-refund.");
    }
    if (current.paymentStatus === "REFUNDED") {
      throw new PaymentConfirmationConflict("Pembayaran sudah di-refund.");
    }
    const withProof = params.expectedProofVersion !== undefined;
    if (withProof && (
      !current.paymentProofUrl ||
      current.paymentProofVersion !== params.expectedProofVersion ||
      current.paymentProofStatus !== "PENDING_REVIEW"
    )) {
      throw new PaymentConfirmationConflict("Bukti transfer sudah berubah atau telah direview.");
    }
    const paymentChanged = current.paymentStatus !== "PAID";
    if (!paymentChanged && !params.allowAlreadyPaid && !withProof) {
      throw new PaymentConfirmationConflict("Pembayaran sudah dikonfirmasi sebelumnya.");
    }

    const reviewedAt = new Date();
    const data = paymentChanged
      ? current.status === "PENDING" && current.orderType === SELF_PICKUP_METHOD
        ? { paymentStatus: "PAID" as const, status: "PROCESSING" as const, pickupStatus: "PREPARING" }
        : current.status === "PENDING"
          ? { paymentStatus: "PAID" as const, status: "PAID" as const }
          : current.orderType === SELF_PICKUP_METHOD
            ? { paymentStatus: "PAID" as const, pickupStatus: "PREPARING" }
            : { paymentStatus: "PAID" as const }
      : {};
    const updated = await tx.order.updateMany({
      where: {
        id: current.id,
        status: { notIn: ["CANCELLED", "REFUNDED"] },
        paymentStatus: paymentChanged ? { notIn: ["PAID", "REFUNDED"] } : "PAID",
        ...(withProof ? {
          paymentProofVersion: params.expectedProofVersion,
          paymentProofStatus: "PENDING_REVIEW" as const,
        } : {}),
      },
      data: {
        ...data,
        ...(withProof ? {
          paymentProofStatus: "VERIFIED" as const,
          paymentProofReviewedAt: reviewedAt,
          paymentProofReviewedBy: params.actorId,
          paymentProofRejectReason: null,
        } : {}),
      },
    });
    if (updated.count !== 1) {
      throw new PaymentConfirmationConflict("Order atau bukti transfer baru saja berubah.");
    }
    if (withProof) {
      const proofUpdated = await tx.orderPaymentProof.updateMany({
        where: {
          orderId: current.id,
          version: params.expectedProofVersion,
          status: "PENDING_REVIEW",
        },
        data: {
          status: "VERIFIED",
          reviewedAt,
          reviewedBy: params.actorId,
          rejectReason: null,
        },
      });
      if (proofUpdated.count !== 1) {
        throw new PaymentConfirmationConflict("Riwayat bukti transfer tidak sinkron.");
      }
    }
    if (paymentChanged) {
      await recordOrderStatusEvent(tx, current.id, "PAID", {
        actorType: "ADMIN",
        actorId: params.actorId,
        idempotencyKey: `admin-payment:${current.id}`,
      });
      if (current.status === "PENDING" && current.orderType === SELF_PICKUP_METHOD) {
        await recordOrderStatusEvent(tx, current.id, "PROCESSING", {
          actorType: "ADMIN",
          actorId: params.actorId,
          idempotencyKey: `admin-processing-after-payment:${current.id}`,
        });
      }
    }
    return { ...current, paymentChanged };
  });

  if (result.paymentChanged) {
    const emailContext = await prisma.order.findUnique({
      where: { id: result.id },
      select: {
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
      },
    });
    if (emailContext) {
      await sendOrderStatusEmail("PAID", emailContext).catch(() => {});
      await sendOrderStatusPush(result.id, emailContext.orderNumber, "PAID").catch(() => {});
    }
    if (result.orderType !== SELF_PICKUP_METHOD) {
      await createBiteshipShipment(result.id).catch((error) => {
        console.error("[biteship] create shipment after manual payment failed", error);
      });
    }
  }
  return result;
}
