import type { Prisma } from "@prisma/client";
import { buildSelfPickupMapsUrl, SELF_PICKUP_METHOD } from "@/lib/self-pickup";

export const memberOrdersInclude = {
  items: {
    select: {
      id: true,
      name: true,
      quantity: true,
      price: true,
      productId: true,
      variantLabel: true,
      product: {
        select: {
          imageUrl: true,
          category: { select: { name: true } },
        },
      },
      reviews: {
        where: { status: { not: "DELETED" } },
        select: { id: true },
        take: 1,
      },
    },
  },
  timelineEvents: {
    select: { status: true, occurredAt: true },
    orderBy: [{ occurredAt: "asc" }, { createdAt: "asc" }],
  },
} satisfies Prisma.OrderInclude;

type MemberOrderRecord = Prisma.OrderGetPayload<{ include: typeof memberOrdersInclude }>;

function canonicalLegacyStatusAt(order: MemberOrderRecord) {
  if (order.status === "PENDING") return order.createdAt;
  if (order.status === "READY_FOR_PICKUP") return order.readyForPickupAt;
  if (order.status === "SHIPPED") return order.shippedAt;
  if (order.status === "DELIVERED" && order.orderType === SELF_PICKUP_METHOD) {
    return order.pickedUpAt;
  }
  return null;
}

export function serializeMemberOrder(order: MemberOrderRecord) {
  const latestStatusAt = order.timelineEvents.at(-1)?.occurredAt ?? canonicalLegacyStatusAt(order);
  return {
    id: order.id,
    orderNumber: order.orderNumber,
    createdAt: order.createdAt.toISOString(),
    status: order.status,
    statusUpdatedAt: latestStatusAt?.toISOString() ?? null,
    latestStatusAt: latestStatusAt?.toISOString() ?? null,
    paymentStatus: order.paymentStatus,
    paymentProvider: order.paymentProvider,
    paymentProofUrl: order.paymentProofUrl,
    manualBank: order.manualBank,
    uniqueCode: order.uniqueCode,
    total: order.total,
    subtotal: order.subtotal,
    shippingCost: order.shippingCost,
    discount: order.discount,
    paymentUrl: order.paymentUrl,
    detailUrl: `/orders/${order.orderNumber}`,
    biteshipTrackingUrl: order.biteshipTrackingUrl,
    orderType: order.orderType,
    pickupMapsUrl: buildSelfPickupMapsUrl(),
    timelineEvents: order.timelineEvents.map((event) => ({
      status: event.status,
      occurredAt: event.occurredAt.toISOString(),
    })),
    itemCount: order.items.reduce((sum, item) => sum + item.quantity, 0),
    items: order.items.map((item) => ({
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      price: item.price,
      productId: item.productId,
      variantLabel: item.variantLabel,
      imageUrl: item.product?.imageUrl ?? null,
      categoryName: item.product?.category?.name ?? null,
      reviewed: item.reviews.length > 0,
    })),
  };
}
