import { prisma } from "@/lib/prisma";

export const STAFF_ORDER_SCHEMA_VERSION = 1 as const;

export async function getStaffOrderDetail(orderNumber: string) {
  const order = await prisma.order.findUnique({
    where: { orderNumber },
    select: {
      orderNumber: true,
      status: true,
      paymentStatus: true,
      createdAt: true,
      updatedAt: true,
      subtotal: true,
      shippingCost: true,
      discount: true,
      total: true,
      customerName: true,
      customerPhone: true,
      orderType: true,
      shippingMethod: true,
      shippingAddress: true,
      shippingCity: true,
      shippingPostalCode: true,
      shippingAreaLabel: true,
      shippingProvinceName: true,
      shippingDistrictName: true,
      pickupStoreName: true,
      pickupStoreAddress: true,
      pickupHours: true,
      paymentProvider: true,
      manualBank: true,
      paymentProofUrl: true,
      paymentProofStatus: true,
      paymentProofVersion: true,
      paymentProofUploadedAt: true,
      paymentProofReviewedAt: true,
      paymentProofReviewedBy: true,
      paymentProofRejectReason: true,
      items: {
        orderBy: { id: "asc" as const },
        select: {
          id: true,
          productId: true,
          name: true,
          variantLabel: true,
          quantity: true,
          price: true,
          product: { select: { imageUrl: true } },
        },
      },
      timelineEvents: {
        orderBy: { occurredAt: "asc" as const },
        select: { status: true, occurredAt: true, actorType: true },
      },
    },
  });
  if (!order) return null;

  const proofUrl = order.paymentProofUrl
    ? `/api/chat/staff/orders/${encodeURIComponent(order.orderNumber)}/payment-proof`
    : null;
  return {
    schemaVersion: STAFF_ORDER_SCHEMA_VERSION,
    order: {
      orderNumber: order.orderNumber,
      status: order.status,
      paymentStatus: order.paymentStatus,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
      subtotal: order.subtotal,
      shippingCost: order.shippingCost,
      discount: order.discount,
      total: order.total,
      itemCount: order.items.reduce((sum, item) => sum + item.quantity, 0),
      customer: { name: order.customerName, phone: order.customerPhone },
      fulfillment: {
        type: order.orderType,
        shippingMethod: order.shippingMethod,
        address: order.orderType === "DELIVERY" ? {
          line: order.shippingAddress,
          city: order.shippingCity,
          postalCode: order.shippingPostalCode,
          areaLabel: order.shippingAreaLabel,
          provinceName: order.shippingProvinceName,
          districtName: order.shippingDistrictName,
        } : null,
        pickup: order.orderType !== "DELIVERY" ? {
          storeName: order.pickupStoreName,
          address: order.pickupStoreAddress,
          hours: order.pickupHours,
        } : null,
      },
      payment: {
        provider: order.paymentProvider,
        manualBank: order.manualBank,
        proof: order.paymentProofUrl ? {
          status: order.paymentProofStatus,
          version: order.paymentProofVersion,
          uploadedAt: order.paymentProofUploadedAt,
          reviewedAt: order.paymentProofReviewedAt,
          reviewedBy: order.paymentProofReviewedBy,
          rejectReason: order.paymentProofRejectReason,
          url: proofUrl,
        } : null,
      },
      items: order.items.map((item) => ({
        id: item.id,
        productId: item.productId,
        name: item.name,
        variantLabel: item.variantLabel,
        quantity: item.quantity,
        unitPrice: item.price,
        lineTotal: item.price * item.quantity,
        imageUrl: item.product.imageUrl,
      })),
      timeline: order.timelineEvents,
    },
  };
}
