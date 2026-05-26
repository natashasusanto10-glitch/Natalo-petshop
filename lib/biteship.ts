import type { Order, OrderItem } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import {
  getOriginCoordinates,
  logMissingOriginArea,
  resolveOriginAreaId,
  SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE,
} from "@/lib/shipping-origin";

/**
 * Single source of truth: apakah integrasi Biteship aktif?
 *
 * Natalo opt to skip Biteship saat awal launch karena:
 *   - Aktivasi butuh test orders + verifikasi 1-2 hari
 *   - Kurir instant (Gojek/Grab) tidak ke-cover Biteship anyway
 *   - Volume awal kecil — manual booking masih scalable
 *
 * Logic disable:
 *   - Explicit: env BITESHIP_ENABLED=false → disabled (force-off
 *     walaupun API key ada)
 *   - Implicit: env BITESHIP_API_KEY tidak ada / kosong → disabled
 *     (no key = tidak mungkin call API)
 *
 * Dipakai di:
 *   - createBiteshipShipment / createBiteshipShipmentIfReady (early return)
 *   - app/api/payment/midtrans webhook (skip auto-create)
 *   - app/admin/(protected)/orders/[id]/actions.ts markAsPaid (skip)
 *   - app/api/shipping/rates (fallback ke manual ongkir input)
 *   - app/api/shipping/areas (return empty)
 *   - Admin UI (hide error banner, tampilkan note "manual shipping")
 *
 * Kapan re-enable: set BITESHIP_ENABLED=true + ensure BITESHIP_API_KEY
 * valid + sudah lewat proses aktivasi di dashboard Biteship.
 */
export function isBiteshipEnabled(): boolean {
  if (process.env.BITESHIP_ENABLED === "false") return false;
  if (!process.env.BITESHIP_API_KEY) return false;
  return true;
}

type BiteshipItem = {
  name: string;
  description: string;
  category: string;
  value: number;
  quantity: number;
  weight: number;
  height: number;
  length: number;
  width: number;
};

type OrderWithItems = Order & { items: OrderItem[] };

function isInstantCourier(order: Pick<Order, "courierCode" | "courierService">) {
  const code = (order.courierCode ?? "").toLowerCase();
  const service = (order.courierService ?? "").toLowerCase();
  return ["grab", "gojek"].includes(code) || service.includes("instant") || service.includes("same_day");
}

function buildItems(items: OrderItem[]): BiteshipItem[] {
  return items.map((item) => ({
    name: item.name.slice(0, 100),
    description: item.variantLabel ? `${item.name} - ${item.variantLabel}`.slice(0, 100) : item.name.slice(0, 100),
    category: "others",
    value: Math.max(0, item.price),
    quantity: Math.max(1, item.quantity),
    weight: Math.max(1, item.weightGram),
    height: 10,
    length: 10,
    width: 10,
  }));
}

async function getCreateOrderPayload(order: OrderWithItems) {
  const { latitude: originLatitude, longitude: originLongitude } =
    getOriginCoordinates();
  const originAreaId = await resolveOriginAreaId();
  const destinationLatitude = order.shippingLatitude;
  const destinationLongitude = order.shippingLongitude;
  const instant = isInstantCourier(order);

  if (!process.env.BITESHIP_API_KEY) {
    throw new Error("BITESHIP_API_KEY belum di-set.");
  }
  if (!order.courierCode || !order.courierService) {
    throw new Error("Kurir belum dipilih.");
  }
  if (!instant && !originAreaId) {
    logMissingOriginArea();
    throw new Error(SHIPPING_ORIGIN_UNAVAILABLE_MESSAGE);
  }
  if (!instant && !order.shippingAreaId) {
    throw new Error("Area Biteship tujuan belum dipilih.");
  }
  if (instant && (originLatitude === null || originLongitude === null)) {
    throw new Error("Koordinat pickup toko wajib diisi untuk kurir instant.");
  }
  if (instant && (destinationLatitude === null || destinationLongitude === null)) {
    throw new Error("Koordinat tujuan wajib diisi untuk kurir instant.");
  }

  return {
    shipper_contact_name: process.env.SHOP_ORIGIN_CONTACT_NAME || process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop",
    shipper_contact_phone: process.env.SHOP_ORIGIN_CONTACT_PHONE || process.env.NEXT_PUBLIC_WA_NUMBER || "",
    shipper_contact_email: process.env.SHOP_ORIGIN_CONTACT_EMAIL || undefined,
    shipper_organization: process.env.SHOP_ORIGIN_ORGANIZATION || process.env.NEXT_PUBLIC_BRAND_NAME || "Natalo Petshop",
    origin_contact_name: process.env.SHOP_ORIGIN_CONTACT_NAME || "Natalo Petshop",
    origin_contact_phone: process.env.SHOP_ORIGIN_CONTACT_PHONE || process.env.NEXT_PUBLIC_WA_NUMBER || "",
    origin_address: process.env.SHOP_ORIGIN_ADDRESS || process.env.NEXT_PUBLIC_STORE_ADDRESS || "",
    origin_note: process.env.SHOP_ORIGIN_NOTE || undefined,
    origin_area_id: instant ? undefined : originAreaId,
    origin_postal_code: instant ? undefined : Number(process.env.SHOP_ORIGIN_POSTAL_CODE || 0) || undefined,
    origin_coordinate:
      originLatitude !== null && originLongitude !== null
        ? { latitude: originLatitude, longitude: originLongitude }
        : undefined,
    destination_contact_name: order.customerName,
    destination_contact_phone: order.customerPhone,
    destination_contact_email: order.customerEmail || undefined,
    destination_address: order.shippingAddress,
    destination_note: order.shippingPinpointAddress || order.notes || undefined,
    destination_area_id: instant ? undefined : order.shippingAreaId || undefined,
    destination_postal_code: Number(order.shippingPostalCode || 0) || undefined,
    destination_coordinate:
      destinationLatitude !== null && destinationLongitude !== null
        ? { latitude: destinationLatitude, longitude: destinationLongitude }
        : undefined,
    courier_company: order.courierCode,
    courier_type: order.courierService,
    courier_insurance: Math.max(0, order.subtotal),
    delivery_type: "now",
    order_note: order.notes || undefined,
    reference_id: order.orderNumber,
    metadata: {
      order_id: order.id,
      order_number: order.orderNumber,
      payment_provider: order.paymentProvider,
    },
    items: buildItems(order.items),
  };
}

export async function createBiteshipShipment(orderId: string) {
  // Skip kalau Biteship belum aktif (lihat isBiteshipEnabled comment).
  // Natalo dalam fase awal launch pakai manual flow: admin book di
  // platform kurir sendiri, lalu input resi via form markAsShipped.
  if (!isBiteshipEnabled()) {
    return { skipped: true, reason: "biteship_disabled" } as const;
  }

  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: { items: true },
  });
  if (!order) throw new Error("Order tidak ditemukan.");
  if (order.biteshipOrderId) return { skipped: true, order };
  if (order.paymentStatus !== "PAID") {
    throw new Error("Order belum lunas, shipment belum bisa dibuat.");
  }
  if (order.status === "CANCELLED" || order.status === "REFUNDED") {
    throw new Error("Order sudah dibatalkan/refund.");
  }

  const payload = await getCreateOrderPayload(order);

  try {
    await prisma.order.update({
      where: { id: order.id },
      data: {
        shipmentStatus: "CREATING",
        biteshipError: null,
        biteshipRequest: payload,
      },
    });

    const response = await fetch("https://api.biteship.com/v1/orders", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: process.env.BITESHIP_API_KEY || "",
      },
      body: JSON.stringify(payload),
    });
    const data = await response.json().catch(() => ({}));

    if (!response.ok || data?.success === false) {
      const message = data?.error || data?.message || `Biteship error ${response.status}`;
      await prisma.order.update({
        where: { id: order.id },
        data: {
          shipmentStatus: "FAILED",
          biteshipError: String(message),
          biteshipResponse: data,
        },
      });
      throw new Error(String(message));
    }

    const courier = data?.courier ?? {};
    const trackingNumber =
      courier?.waybill_id ||
      courier?.tracking_id ||
      data?.waybill_id ||
      data?.tracking_id ||
      order.trackingNumber;

    await prisma.order.update({
      where: { id: order.id },
      data: {
        biteshipOrderId: data?.id ? String(data.id) : null,
        shipmentStatus: String(data?.status || "CREATED").toUpperCase(),
        trackingNumber: trackingNumber ? String(trackingNumber) : null,
        biteshipTrackingUrl: data?.courier?.link || data?.tracking_url || null,
        biteshipResponse: data,
        biteshipError: null,
      },
    });

    return { skipped: false, order, response: data };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Gagal membuat shipment Biteship.";
    await prisma.order.update({
      where: { id: order.id },
      data: {
        shipmentStatus: "FAILED",
        biteshipError: message,
      },
    });
    throw error;
  }
}

export async function createBiteshipShipmentIfReady(orderId: string) {
  try {
    return await createBiteshipShipment(orderId);
  } catch (error) {
    console.error("[biteship] create shipment failed", { orderId, error });
    return null;
  }
}
