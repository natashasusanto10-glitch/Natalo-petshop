import type { OrderStatus, Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";

type OrderActorType = "SYSTEM" | "CUSTOMER" | "ADMIN" | "PAYMENT_PROVIDER" | "CRON";

export type OrderTransitionContext = {
  actorType?: OrderActorType;
  actorId?: string | null;
  occurredAt?: Date;
  metadata?: Prisma.InputJsonValue;
  idempotencyKey?: string;
};

const ALLOWED: Record<OrderStatus, OrderStatus[]> = {
  PENDING: ["PAID", "PROCESSING", "CANCELLED"],
  PAID: ["PROCESSING", "CANCELLED"],
  PROCESSING: ["READY_FOR_PICKUP", "SHIPPED", "CANCELLED"],
  READY_FOR_PICKUP: ["DELIVERED", "CANCELLED"],
  SHIPPED: ["DELIVERED"],
  DELIVERED: [],
  CANCELLED: [],
  REFUNDED: [],
};

export function canTransitionOrderStatus(from: OrderStatus, to: OrderStatus) {
  return ALLOWED[from]?.includes(to) ?? false;
}

export function assertCanTransitionOrderStatus(from: OrderStatus, to: OrderStatus) {
  if (!canTransitionOrderStatus(from, to)) {
    throw new Error(`Transisi status order tidak valid: ${from} -> ${to}`);
  }
}

export async function recordOrderStatusEvent(
  tx: Prisma.TransactionClient,
  orderId: string,
  status: OrderStatus,
  context: OrderTransitionContext = {},
) {
  const data = {
    orderId,
    status,
    occurredAt: context.occurredAt ?? new Date(),
    actorType: context.actorType ?? "SYSTEM",
    actorId: context.actorId ?? null,
    metadata: context.metadata,
    idempotencyKey: context.idempotencyKey,
  };
  if (context.idempotencyKey) {
    return tx.orderStatusHistory.upsert({
      where: { idempotencyKey: context.idempotencyKey },
      update: {},
      create: data,
      select: { id: true },
    });
  }
  return tx.orderStatusHistory.create({ data, select: { id: true } });
}

export async function transitionOrderStatus(
  orderId: string,
  to: OrderStatus,
  data: Prisma.OrderUpdateManyMutationInput = {},
  context: OrderTransitionContext = {},
) {
  return prisma.$transaction(async (tx) => {
    if (context.idempotencyKey) {
      const existing = await tx.orderStatusHistory.findUnique({
        where: { idempotencyKey: context.idempotencyKey },
        select: { id: true },
      });
      if (existing) return { changed: false, idempotent: true };
    }
    const order = await tx.order.findUnique({ where: { id: orderId }, select: { status: true } });
    if (!order) throw new Error("Order tidak ditemukan.");
    assertCanTransitionOrderStatus(order.status, to);
    const result = await tx.order.updateMany({
      where: { id: orderId, status: order.status },
      data: { ...data, status: to },
    });
    if (result.count === 0) throw new Error("Order sudah berubah, refresh dulu.");
    await recordOrderStatusEvent(tx, orderId, to, context);
    return { changed: true, idempotent: false };
  });
}
