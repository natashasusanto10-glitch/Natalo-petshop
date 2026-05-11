import webpush from "web-push";
import { prisma } from "./prisma";
import { buildOrderDetailPath } from "./order-detail";
import { sendApnsToUser } from "./apns";
import { sendFcmToUser } from "./fcm";

function getVapidConfig() {
  const publicKey = process.env.VAPID_PUBLIC_KEY;
  const privateKey = process.env.VAPID_PRIVATE_KEY;
  const subject = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
  return { publicKey, privateKey, subject };
}

export type PushPayload = {
  title: string;
  body: string;
  url?: string;
  /** Group key — notification dgn tag sama akan replace existing, bukan stack */
  tag?: string;
  /** Action buttons (Android only — iOS Safari ignore) */
  actions?: Array<{ action: string; title: string }>;
  /** Require user interaction sebelum auto-dismiss */
  requireInteraction?: boolean;
};

export async function sendPushToUser(userId: string, payload: PushPayload) {
  const { publicKey, privateKey } = getVapidConfig();
  if (!publicKey || !privateKey) return;

  webpush.setVapidDetails(`mailto:admin@toko.com`, publicKey, privateKey);

  // Filter: cuma Web Push subscriptions (HTTPS endpoint).
  // - APNs tokens ("apns:...") → sendApnsToUser() di lib/apns.ts
  // - FCM tokens ("fcm:...")  → sendFcmToUser() di lib/fcm.ts
  const subs = await prisma.pushSubscription
    .findMany({
      where: {
        userId,
        endpoint: { startsWith: "https://" },
      },
    })
    .catch(() => []);
  const data = JSON.stringify(payload);

  await Promise.allSettled(
    subs.map(async (sub) => {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          data,
        );
      } catch (err: unknown) {
        // Remove expired/invalid subscriptions
        if (err && typeof err === "object" && "statusCode" in err && (err.statusCode === 404 || err.statusCode === 410)) {
          await prisma.pushSubscription.delete({ where: { id: sub.id } }).catch(() => {});
        }
      }
    }),
  );
}

const STATUS_TITLES: Record<string, string> = {
  PAID: "💰 Pembayaran Diterima",
  PROCESSING: "📦 Pesanan Disiapkan",
  SHIPPED: "🚚 Pesanan Dikirim",
  DELIVERED: "✅ Pesanan Sampai",
  CANCELLED: "❌ Pesanan Dibatalkan",
  REFUNDED: "💸 Refund Diproses",
};

/**
 * Push notification untuk update status order. Fire-and-forget — caller
 * wrap dgn .catch() supaya tidak block flow.
 *
 * Format body custom per status:
 * - PAID: konfirmasi simple
 * - PROCESSING: simple
 * - SHIPPED: include nomor AWB + kurir (kalau tersedia)
 * - DELIVERED: include CTA review
 * - CANCELLED / REFUNDED: simple
 *
 * Tag konsisten per orderNumber → notification baru replace lama
 * (tidak stack 5 notif untuk 1 order yg status-nya berubah-ubah).
 */
export async function sendOrderStatusPush(orderId: string, orderNumber: string, status: string) {
  const order = await prisma.order
    .findUnique({
      where: { id: orderId },
      select: {
        userId: true,
        trackingToken: true,
        trackingNumber: true,
        courierCode: true,
        courierService: true,
      },
    })
    .catch(() => null);
  if (!order?.userId) return;

  const url = buildOrderDetailPath(orderNumber, order.trackingToken);
  const title = STATUS_TITLES[status];
  if (!title) return;

  // Body construction per status
  let body = "";
  let actions: PushPayload["actions"] | undefined;
  let requireInteraction = false;

  switch (status) {
    case "PAID":
      body = `Pembayaran ${orderNumber} dikonfirmasi. Pesanan sedang disiapkan.`;
      break;
    case "PROCESSING":
      body = `Pesanan ${orderNumber} sedang dipacking tim kami.`;
      break;
    case "SHIPPED": {
      const parts: string[] = [];
      const courier = (order.courierService || order.courierCode || "").trim();
      if (courier) parts.push(courier.toUpperCase());
      if (order.trackingNumber) parts.push(`AWB ${order.trackingNumber}`);
      body = parts.length
        ? `${orderNumber} dikirim via ${parts.join(" · ")}. Tap untuk tracking.`
        : `Pesanan ${orderNumber} sudah dikirim. Tap untuk lihat detail.`;
      actions = [{ action: "track", title: "Lacak Paket" }];
      requireInteraction = true;
      break;
    }
    case "DELIVERED":
      body = `Pesanan ${orderNumber} sudah sampai. Bantu beri rating untuk produk yang kamu beli 🌟`;
      actions = [{ action: "review", title: "Beri Review" }];
      break;
    case "CANCELLED":
      body = `Pesanan ${orderNumber} dibatalkan. Hubungi admin kalau ada pertanyaan.`;
      break;
    case "REFUNDED":
      body = `Refund untuk ${orderNumber} sudah diproses. Dana akan masuk dalam 3-5 hari kerja.`;
      break;
    default:
      return;
  }

  const payload: PushPayload = {
    title,
    body,
    url,
    tag: `order-${orderNumber}`, // konsisten per order — replace existing
    actions,
    requireInteraction,
  };

  // Kirim ke 3 channel paralel:
  // - Web Push (PWA Safari, Chrome Android, desktop browsers) via VAPID
  // - APNs   (iOS native app via TestFlight/App Store) via @parse/node-apn
  // - FCM    (Android native app via Play Store) via firebase-admin
  // Subs disimpan di table sama (PushSubscription), dibedakan endpoint prefix:
  //   "https://..." → Web Push, "apns:..." → APNs, "fcm:..." → FCM.
  await Promise.all([
    sendPushToUser(order.userId, payload),
    sendApnsToUser(order.userId, payload),
    sendFcmToUser(order.userId, payload),
  ]);
}
