import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { buildSelfPickupMapsUrl } from "@/lib/self-pickup";

export const dynamic = "force-dynamic";

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const orders = await prisma.order.findMany({
    where: { userId: session.sub },
    orderBy: { createdAt: "desc" },
    take: 50,
    include: {
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
        },
      },
    },
  });

  return NextResponse.json({
    orders: orders.map((order) => ({
      id: order.id,
      orderNumber: order.orderNumber,
      createdAt: order.createdAt.toISOString(),
      status: order.status,
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
      })),
    })),
  });
}
