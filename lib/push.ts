import webpush from "web-push";
import { prisma } from "./prisma";
import { buildOrderDetailPath } from "./order-detail";
import { sendApnsToUser } from "./apns";

function getVapidConfig() {
  const publicKey = process.env.VAPID_PUBLIC_KEY;
  const privateKey = process.env.VAPID_PRIVATE_KEY;
  const subject = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";
  return { publicKey, privateKey, subject };
}

export async function sendPushToUser(userId: string, payload: { title: string; body: string; url?: string }) {
  const { publicKey, privateKey, subject } = getVapidConfig();
  if (!publicKey || !privateKey) return;

  webpush.setVapidDetails(`mailto:admin@toko.com`, publicKey, privateKey);

  // Filter: cuma Web Push subscriptions (HTTPS endpoint).
  // APNs tokens (endpoint "apns:...") di-handle sendApnsToUser() di lib/apns.ts.
  const subs = await prisma.pushSubscription
    .findMany({
      where: { userId, NOT: { endpoint: { startsWith: "apns:" } } },
    })
    .catch(() => []);
  const data = JSON.stringify(payload);

  await Promise.allSettled(
    subs.map(async (sub) => {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          data
        );
      } catch (err: unknown) {
        // Remove expired/invalid subscriptions
        if (err && typeof err === "object" && "statusCode" in err && (err.statusCode === 404 || err.statusCode === 410)) {
          await prisma.pushSubscription.delete({ where: { id: sub.id } }).catch(() => {});
        }
      }
    })
  );
}

export async function sendOrderStatusPush(orderId: string, orderNumber: string, status: string) {
  const order = await prisma.order.findUnique({ where: { id: orderId }, select: { userId: true, trackingToken: true } }).catch(() => null);
  if (!order?.userId) return;

  const statusMessages: Record<string, string> = {
    PAID: "Pembayaranmu sudah dikonfirmasi! Pesanan sedang disiapkan.",
    PROCESSING: "Pesananmu sedang dipacking oleh tim kami.",
    SHIPPED: "Pesananmu sudah dikirim! Cek nomor resi di halaman order.",
    DELIVERED: "Pesananmu sudah sampai! Terima kasih sudah belanja.",
    CANCELLED: "Pesananmu dibatalkan.",
  };

  const body = statusMessages[status];
  if (!body) return;

  const url = buildOrderDetailPath(orderNumber, order.trackingToken);
  const payload = {
    title: "Update Pesanan 🛍️",
    body,
    url,
  };

  // Kirim ke 2 channel paralel:
  // - Web Push (PWA Safari, Chrome Android, dll) via VAPID
  // - APNs (iOS native app via TestFlight/App Store) via @parse/node-apn
  // Subs disimpan di table sama (PushSubscription), dibedakan dari endpoint
  // prefix: "apns:..." → APNs, "https://..." → Web Push.
  // Existing sendPushToUser() filter ke endpoint Web Push. sendApnsToUser()
  // filter ke endpoint apns:.
  await Promise.all([
    sendPushToUser(order.userId, payload),
    sendApnsToUser(order.userId, payload),
  ]);
}
