import { randomBytes } from "crypto";
import type { Prisma } from "@prisma/client";
import { SELF_PICKUP_METHOD, SELF_PICKUP_STORE, buildSelfPickupMapsUrl } from "@/lib/self-pickup";

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
      product: {
        select: {
          slug: true,
          imageUrl: true,
        },
      },
      reviews: {
        where: { status: { not: "DELETED" } },
        select: { id: true },
        take: 1,
      },
    },
  },
} satisfies Prisma.OrderInclude;

export type OrderDetailRecord = Prisma.OrderGetPayload<{
  include: typeof orderDetailInclude;
}>;

export function createTrackingToken() {
  return randomBytes(24).toString("hex");
}

export function buildOrderDetailPath(
  orderNumber: string,
  trackingToken?: string | null
) {
  const path = `/pesanan/${encodeURIComponent(orderNumber)}`;
  return trackingToken
    ? `${path}?token=${encodeURIComponent(trackingToken)}`
    : path;
}

export function buildOrderDetailUrl(
  orderNumber: string,
  trackingToken?: string | null
) {
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
  return `${siteUrl}${buildOrderDetailPath(orderNumber, trackingToken)}`;
}

export function buildOrderSuccessPath(
  orderNumber: string,
  trackingToken?: string | null
) {
  const path = `/pesanan/${encodeURIComponent(orderNumber)}/success`;
  return trackingToken
    ? `${path}?token=${encodeURIComponent(trackingToken)}`
    : path;
}

export function buildOrderSuccessUrl(
  orderNumber: string,
  trackingToken?: string | null
) {
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
  return `${siteUrl}${buildOrderSuccessPath(orderNumber, trackingToken)}`;
}

export function isOrderContactMatch(
  order: { customerEmail?: string | null; customerPhone: string },
  contact: string
) {
  const raw = contact.trim().toLowerCase();
  const email = order.customerEmail?.trim().toLowerCase();
  const digits = raw.replace(/\D/g, "");
  const phoneDigits = order.customerPhone.replace(/\D/g, "");
  const normalizedInput = digits.startsWith("0")
    ? `62${digits.slice(1)}`
    : digits;
  const normalizedPhone = phoneDigits.startsWith("0")
    ? `62${phoneDigits.slice(1)}`
    : phoneDigits;

  return Boolean(
    (email && email === raw) ||
      (normalizedInput && normalizedInput === normalizedPhone)
  );
}

export function serializeOrderDetail(order: OrderDetailRecord) {
  const isSelfPickup = order.orderType === SELF_PICKUP_METHOD;

  return {
    id: order.id,
    orderNumber: order.orderNumber,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    customerEmail: order.customerEmail,
    status: order.status,
    paymentStatus: order.paymentStatus,
    paymentProvider: order.paymentProvider,
    paymentProofUrl: order.paymentProofUrl,
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
    orderType: order.orderType,
    shippingMethod: order.shippingMethod,
    courierCode: order.courierCode,
    courierService: order.courierService,
    trackingNumber: order.trackingNumber,
    shipmentStatus: order.shipmentStatus,
    biteshipTrackingUrl: order.biteshipTrackingUrl,
    pickupStoreName: isSelfPickup
      ? order.pickupStoreName ?? SELF_PICKUP_STORE.name
      : order.pickupStoreName,
    pickupStoreAddress: isSelfPickup
      ? order.pickupStoreAddress ?? SELF_PICKUP_STORE.address
      : order.pickupStoreAddress,
    pickupStoreLatitude: order.pickupStoreLatitude,
    pickupStoreLongitude: order.pickupStoreLongitude,
    pickupHours: isSelfPickup ? order.pickupHours ?? SELF_PICKUP_STORE.hours : order.pickupHours,
    pickupCode: order.pickupCode,
    pickupQrCode: order.pickupQrCode,
    pickupStatus: order.pickupStatus,
    readyForPickupAt: order.readyForPickupAt?.toISOString() ?? null,
    pickedUpAt: order.pickedUpAt?.toISOString() ?? null,
    pickupMapsUrl: buildSelfPickupMapsUrl(),
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
      productSlug: item.product.slug,
      productImage: item.product.imageUrl,
      reviewed: item.reviews.length > 0,
    })),
  };
}

export type SerializedOrderDetail = ReturnType<typeof serializeOrderDetail>;

export function getFirstReviewableOrderItem<
  T extends { reviewed: boolean }
>(params: {
  status: string;
  canReview: boolean;
  items: readonly T[];
}): T | null {
  if (!params.canReview || params.status !== "DELIVERED") return null;
  return params.items.find((item) => !item.reviewed) ?? null;
}
