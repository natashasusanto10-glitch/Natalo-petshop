import type { OrderStatus, Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";

const ALLOWED: Record<OrderStatus, OrderStatus[]> = {
  PENDING: ["PROCESSING", "CANCELLED"],
  PAID: ["PROCESSING", "CANCELLED"],
  PROCESSING: ["SHIPPED", "CANCELLED"],
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

export async function transitionOrderStatus(
  orderId: string,
  to: OrderStatus,
  data: Prisma.OrderUpdateManyMutationInput = {}
) {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    select: { status: true },
  });
  if (!order) throw new Error("Order tidak ditemukan.");

  assertCanTransitionOrderStatus(order.status, to);

  const result = await prisma.order.updateMany({
    where: { id: orderId, status: order.status },
    data: { ...data, status: to },
  });
  if (result.count === 0) {
    throw new Error("Order sudah berubah, refresh dulu.");
  }
}
