import { requireCustomerSession } from "@/lib/session-guards";
import { prisma } from "@/lib/prisma";
import { buildSelfPickupMapsUrl } from "@/lib/self-pickup";
import { OrderErrorState, OrderHistoryClient } from "./OrderHistoryClient";

export default async function MemberOrdersPage() {
  const session = await requireCustomerSession();

  try {
    const orders = await prisma.order.findMany({
      where: { userId: session.sub },
      orderBy: { createdAt: "desc" },
      include: {
        items: {
          select: {
            id: true,
            name: true,
            quantity: true,
            price: true,
            productId: true,
            product: {
              select: {
                imageUrl: true,
                category: { select: { name: true } },
              },
            },
          },
        },
      },
    });

    return (
      <OrderHistoryClient
        orders={orders.map((order) => ({
          id: order.id,
          orderNumber: order.orderNumber,
          createdAt: order.createdAt.toISOString(),
          status: order.status,
          paymentStatus: order.paymentStatus,
          total: order.total,
          subtotal: order.subtotal,
          paymentUrl: order.paymentUrl,
          biteshipTrackingUrl: order.biteshipTrackingUrl,
          orderType: order.orderType,
          pickupMapsUrl: buildSelfPickupMapsUrl(),
          items: order.items.map((item) => ({
            id: item.id,
            name: item.name,
            quantity: item.quantity,
            price: item.price,
            productId: item.productId,
            imageUrl: item.product?.imageUrl ?? null,
            categoryName: item.product?.category?.name ?? null,
          })),
        }))}
      />
    );
  } catch {
    return <OrderErrorState />;
  }
}
