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
  // Voucher usage list — per-voucher discount amount + tipe. Customer
  // UI tampilin "NATA-DISC (-Rp 2.500)" inline supaya user lihat
  // voucher mereka beneran ke-apply. Sebelumnya cuma kode tanpa nominal
  // = customer skeptis "voucher saya kepake gak?".
  voucherUsages: {
    select: {
      voucherType: true,
      discountAmount: true,
      voucher: {
        select: {
          code: true,
          name: true,
          type: true,
          discountScope: true,
        },
      },
    },
    orderBy: { usedAt: "asc" },
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

// Window pembayaran manual = createdAt + AUTO_CANCEL_MANUAL_HOURS (default
// 24 jam). HARUS mirror logika cron auto-cancel-unpaid-manual supaya
// countdown di app akurat (kalau cron pakai 24 jam, app tidak boleh
// tampil window beda). Deadline cuma relevan saat order MANUAL masih
// nunggu bayar & belum upload bukti — setelah bukti masuk, auto-cancel
// berhenti (lihat guard paymentProofUrl di cron) jadi tidak ada deadline.
function manualPaymentDeadlineIso(order: OrderDetailRecord): string | null {
  if (order.paymentProvider !== "MANUAL") return null;
  if (order.paymentStatus !== "PENDING") return null;
  if (order.status !== "PENDING") return null;
  if (order.paymentProofUrl) return null;
  const hoursEnv = process.env.AUTO_CANCEL_MANUAL_HOURS;
  const parsed = hoursEnv ? parseInt(hoursEnv, 10) : 24;
  const hours = Number.isFinite(parsed) && parsed > 0 ? parsed : 24;
  return new Date(
    order.createdAt.getTime() + hours * 60 * 60 * 1000
  ).toISOString();
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
    // Granular discount breakdown — split per kategori supaya customer
    // UI bisa tampilin "Diskon Produk -Rp X" + "Diskon Ongkir -Rp Y"
    // separately. Schema sudah track per-kategori (lihat /api/orders
    // line 468-482), cuma serializer belum expose.
    productDiscount: order.productDiscount,
    shippingDiscount: order.shippingDiscount,
    refundBalanceUsed: order.refundBalanceUsed,
    total: order.total,
    manualBank: order.manualBank,
    uniqueCode: order.uniqueCode,
    voucherCode: order.voucherCode,
    productVoucherCode: order.productVoucherCode,
    shippingVoucherCode: order.shippingVoucherCode,
    // Backend save voucher gratis ongkir ke field ini (lihat
    // /api/orders/route.ts line 643). Sebelumnya gak di-expose → bug
    // affect customer + admin UI invisible voucher ongkir.
    freeShippingVoucherCode: order.freeShippingVoucherCode,
    loyaltyVoucherCode: order.loyaltyVoucherCode,
    manualVoucherCode: order.manualVoucherCode,
    // Alias untuk manualVoucherCode di flow checkout terbaru
    // (PRIVATE_MANUAL_CODE type). Backend save ke salah satu — fallback
    // chain di client/admin display.
    privateVoucherCode: order.privateVoucherCode,
    // Per-voucher discount amount detail — customer UI iterate untuk
    // tampilin nominal per voucher inline. Cegah customer komplain
    // "voucher saya kepake gak?".
    voucherUsages: order.voucherUsages.map((u) => ({
      voucherType: u.voucherType,
      discountAmount: u.discountAmount,
      code: u.voucher.code,
      name: u.voucher.name,
      type: u.voucher.type,
      discountScope: u.voucher.discountScope,
    })),
    shippingAddress: order.shippingAddress,
    shippingCity: order.shippingCity,
    shippingPostalCode: order.shippingPostalCode,
    shippingPinpointAddress: order.shippingPinpointAddress,
    orderType: order.orderType,
    shippingMethod: order.shippingMethod,
    courierCode: order.courierCode,
    courierService: order.courierService,
    trackingNumber: order.trackingNumber,
    // Info driver untuk kurir instant (Gojek/Grab/Lalamove). Diisi
    // sebagai alternatif trackingNumber. Customer UI tampilin kondisional:
    // kalau ada resi → tampilkan resi, else kalau ada driverInfo →
    // tampilkan info driver.
    shippingDriverInfo: order.shippingDriverInfo,
    // Timestamp saat shipment ditandai SHIPPED. Pakai untuk hitung
    // auto-confirm date di Flutter (shippedAt + 7 hari).
    shippedAt: order.shippedAt?.toISOString() ?? null,
    // Pre-computed timestamp kapan order akan otomatis ditandai
    // DELIVERED kalau user tidak tap "Sudah Diterima" duluan.
    // Sinkron dengan cron /api/cron/auto-confirm-delivered (default 7d).
    // Null kalau order belum SHIPPED.
    autoConfirmAt: order.shippedAt
      ? new Date(
          order.shippedAt.getTime() + 7 * 24 * 60 * 60 * 1000,
        ).toISOString()
      : null,
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
    // Cancellation request fields — null untuk order yang belum pernah
    // di-request batal. Status: PENDING (menunggu approval admin),
    // APPROVED (sudah disetujui, order udah CANCELLED), REJECTED (ditolak,
    // order tetap aktif).
    cancellationRequestStatus: order.cancellationRequestStatus,
    cancellationReason: order.cancellationReason,
    cancellationRequestedAt: order.cancellationRequestedAt?.toISOString() ?? null,
    cancellationRespondedAt: order.cancellationRespondedAt?.toISOString() ?? null,
    cancellationRejectReason: order.cancellationRejectReason,
    createdAt: order.createdAt.toISOString(),
    updatedAt: order.updatedAt.toISOString(),
    // Batas waktu bayar transfer manual (countdown di app). Null untuk
    // non-manual / sudah bayar / sudah upload bukti.
    paymentDeadline: manualPaymentDeadlineIso(order),
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
