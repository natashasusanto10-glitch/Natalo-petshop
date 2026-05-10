import { randomBytes } from "crypto";
import type { Prisma } from "@prisma/client";

export const orderDetailInclude = {
  items: {
    select: {
      id: true,
      name: true,
      quantity: true,
      price: true,
      variantLabel: true,
      productId: true,
      variantId: true,
    },
  },
} satisfies Prisma.OrderInclude;

export type OrderDetailRecord = Prisma.OrderGetPayload<{
  include: typeof orderDetailInclude;
}>;

export function createTrackingToken() {
  return randomBytes(24).toString("hex");
}

export function buildOrderDetailPath(orderNumber: string, trackingToken?: string | null) {
  const path = `/pesanan/${encodeURIComponent(orderNumber)}`;
  return trackingToken ? `${path}?token=${encodeURIComponent(trackingToken)}` : path;
}

export function buildOrderDetailUrl(orderNumber: string, trackingToken?: string | null) {
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
  return `${siteUrl}${buildOrderDetailPath(orderNumber, trackingToken)}`;
}

export function isOrderContactMatch(order: { customerEmail?: string | null; customerPhone: string }, contact: string) {
  const raw = contact.trim().toLowerCase();
  const email = order.customerEmail?.trim().toLowerCase();
  const digits = raw.replace(/\D/g, "");
  const phoneDigits = order.customerPhone.replace(/\D/g, "");
  const normalizedInput = digits.startsWith("0") ? `62${digits.slice(1)}` : digits;
  const normalizedPhone = phoneDigits.startsWith("0") ? `62${phoneDigits.slice(1)}` : phoneDigits;

  return Boolean((email && email === raw) || (normalizedInput && normalizedInput === normalizedPhone));
}

export function serializeOrderDetail(order: OrderDetailRecord) {
  return {
    id: order.id,
    orderNumber: order.orderNumber,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    customerEmail: order.customerEmail,
    status: order.status,
    paymentStatus: order.paymentStatus,
    paymentProvider: order.paymentProvider,
    paymentUrl: order.paymentUrl,
    paymentReference: order.paymentReference,
    subtotal: order.subtotal,
    shippingCost: order.shippingCost,
    discount: order.discount,
    total: order.total,
    manualBank: order.manualBank,
    uniqueCode: order.uniqueCode,
    voucherCode: order.voucherCode,
    manualVoucherCode: order.manualVoucherCode,
    shippingAddress: order.shippingAddress,
    shippingCity: order.shippingCity,
    shippingPostalCode: order.shippingPostalCode,
    shippingPinpointAddress: order.shippingPinpointAddress,
    courierCode: order.courierCode,
    courierService: order.courierService,
    trackingNumber: order.trackingNumber,
    shipmentStatus: order.shipmentStatus,
    biteshipTrackingUrl: order.biteshipTrackingUrl,
    notes: order.notes,
    createdAt: order.createdAt.toISOString(),
    updatedAt: order.updatedAt.toISOString(),
    items: order.items.map((item) => ({
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      price: item.price,
      variantLabel: item.variantLabel,
      productId: item.productId,
      variantId: item.variantId,
    })),
  };
}

export type SerializedOrderDetail = ReturnType<typeof serializeOrderDetail>;
