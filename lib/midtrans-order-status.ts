import type { OrderStatus, Prisma } from "@prisma/client";
import { recordOrderStatusEvent } from "@/lib/order-transitions";
import { SELF_PICKUP_METHOD } from "@/lib/self-pickup";

type MidtransOrderSnapshot = {
  id: string;
  orderType: string;
};

export async function applyMidtransPaidStatus(
  tx: Prisma.TransactionClient,
  order: MidtransOrderSnapshot,
  transactionStatus: string,
) {
  const nextStatus: OrderStatus =
    order.orderType === SELF_PICKUP_METHOD ? "PROCESSING" : "PAID";
  const advanced = await tx.order.updateMany({
    where: { id: order.id, status: "PENDING", paymentStatus: { not: "REFUNDED" } },
    data: {
      paymentStatus: "PAID",
      status: nextStatus,
      pickupStatus: order.orderType === SELF_PICKUP_METHOD ? "PREPARING" : undefined,
    },
  });

  if (advanced.count === 0) {
    await tx.order.updateMany({
      where: { id: order.id, paymentStatus: { not: "REFUNDED" } },
      data: { paymentStatus: "PAID" },
    });
    return tx.order.findUniqueOrThrow({ where: { id: order.id } });
  }

  await recordOrderStatusEvent(tx, order.id, "PAID", {
    actorType: "PAYMENT_PROVIDER",
    actorId: "MIDTRANS",
    idempotencyKey: `midtrans:${order.id}:paid`,
    metadata: { transactionStatus },
  });
  if (order.orderType === SELF_PICKUP_METHOD) {
    await recordOrderStatusEvent(tx, order.id, "PROCESSING", {
      actorType: "PAYMENT_PROVIDER",
      actorId: "MIDTRANS",
      idempotencyKey: `midtrans:${order.id}:processing-after-paid`,
    });
  }
  return tx.order.findUniqueOrThrow({ where: { id: order.id } });
}
