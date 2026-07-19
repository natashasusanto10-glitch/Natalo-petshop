import webpush from "web-push";
import { prisma } from "./prisma";
import { buildOrderDetailPath } from "./order-detail";
import { sendFcmToUser } from "./fcm";
import {
  isPushCategoryEnabled,
  type NotificationCategory,
} from "./notification-preferences";

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
  data?: Record<string, string>;
  /** Group key — notification dgn tag sama akan replace existing, bukan stack */
  tag?: string;
  /** Action buttons (Android only — iOS Safari ignore) */
  actions?: Array<{ action: string; title: string }>;
  /** Require user interaction sebelum auto-dismiss */
  requireInteraction?: boolean;
  /** Image attachment URL — Web Push: shown sebagai image di notification.
   *  APNs: di-pass ke NSE untuk fetch + attach. FCM: di-set sebagai image
   *  di notification payload. Format HTTPS JPEG/PNG, max 10 MB. */
  imageUrl?: string | null;
  /** Notification category — APNs only, match dengan UNNotificationCategory
   *  yang di-register di iOS AppDelegate. Trigger action buttons. */
  category?: string | null;
  /** Kategori preferensi user (order|promo|voucher|product|loyalty_points|
   *  chat|feed). Kalau di-set dan user men-disable kategori itu (atau master
   *  switch OFF), push di-skip di server. JANGAN set untuk notif kritikal
   *  (keamanan) yang harus selalu terkirim. */
  prefCategory?: NotificationCategory | null;
};

export async function sendPushToUser(userId: string, payload: PushPayload) {
  const { publicKey, privateKey } = getVapidConfig();
  if (!publicKey || !privateKey) return;

  // Hormati preferensi user — skip channel ini kalau kategori di-mute.
  if (payload.prefCategory) {
    const enabled = await isPushCategoryEnabled(userId, payload.prefCategory);
    if (!enabled) return;
  }

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
          {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.p256dh, auth: sub.auth },
          },
          data
        );
      } catch (err: unknown) {
        // Remove expired/invalid subscriptions
        if (
          err &&
          typeof err === "object" &&
          "statusCode" in err &&
          (err.statusCode === 404 || err.statusCode === 410)
        ) {
          await prisma.pushSubscription
            .delete({ where: { id: sub.id } })
            .catch(() => {});
        }
      }
    })
  );
}

const STATUS_TITLES: Record<string, string> = {
  PAID: "💰 Pembayaran Diterima",
  PROCESSING: "📦 Pesanan Disiapkan",
  SHIPPED: "🚚 Pesanan Dikirim",
  DELIVERED: "✅ Pesanan Sampai",
  CANCELLED: "❌ Pesanan Dibatalkan",
  REFUNDED: "💸 Refund Diproses",
  FAILED: "⏰ Pembayaran Kadaluarsa",
  EXPIRED: "⏰ Pembayaran Kadaluarsa",
};

STATUS_TITLES.READY_FOR_PICKUP = "Pesanan Siap Diambil";

export const ORDER_PUSH_EVENT_TYPE = "order_status_update";

function appendQueryParam(path: string, key: string, value: string) {
  const separator = path.includes("?") ? "&" : "?";
  return `${path}${separator}${encodeURIComponent(key)}=${encodeURIComponent(
    value
  )}`;
}

export function buildOrderStatusPushPayload(params: {
  orderId: string;
  orderNumber: string;
  status: string;
  trackingToken?: string | null;
  trackingNumber?: string | null;
  courierCode?: string | null;
  courierService?: string | null;
  pickupCode?: string | null;
}): PushPayload | null {
  const title = STATUS_TITLES[params.status];
  if (!title) return null;

  const detailPath = buildOrderDetailPath(
    params.orderNumber,
    params.trackingToken
  );
  const url =
    params.status === "DELIVERED"
      ? appendQueryParam(detailPath, "review", "1")
      : detailPath;

  let body = "";
  let actions: PushPayload["actions"] | undefined;
  let requireInteraction = false;

  switch (params.status) {
    case "PAID":
      body = `Pembayaran ${params.orderNumber} dikonfirmasi. Pesanan sedang disiapkan.`;
      break;
    case "PROCESSING":
      body = `Pesanan ${params.orderNumber} sedang dipacking tim kami.`;
      break;
    case "READY_FOR_PICKUP":
      body = `Pesanan kamu sudah siap diambil di Natalo Petshop / Sinar Petstore. Tunjukkan kode ${
        params.pickupCode ?? "-"
      } kepada kasir saat pickup.`;
      requireInteraction = true;
      break;
    case "SHIPPED": {
      const parts: string[] = [];
      const courier = (
        params.courierService ||
        params.courierCode ||
        ""
      ).trim();
      if (courier) parts.push(courier.toUpperCase());
      if (params.trackingNumber) parts.push(`AWB ${params.trackingNumber}`);
      body = parts.length
        ? `${params.orderNumber} dikirim via ${parts.join(
            " - "
          )}. Tap untuk tracking.`
        : `Pesanan ${params.orderNumber} sudah dikirim. Tap untuk lihat detail.`;
      actions = [{ action: "track", title: "Lacak Paket" }];
      requireInteraction = true;
      break;
    }
    case "DELIVERED":
      body = `Pesanan ${params.orderNumber} sudah sampai. Bantu beri rating untuk produk yang kamu beli.`;
      actions = [{ action: "review", title: "Beri Review" }];
      break;
    case "CANCELLED":
      body = `Pesanan ${params.orderNumber} dibatalkan. Hubungi admin kalau ada pertanyaan.`;
      break;
    case "REFUNDED":
      body = `Refund untuk ${params.orderNumber} sudah diproses. Dana akan masuk dalam 3-5 hari kerja.`;
      break;
    default:
      return null;
  }

  return {
    title,
    body,
    url,
    tag: `order-${params.orderNumber}`,
    actions,
    requireInteraction,
    data: {
      type: ORDER_PUSH_EVENT_TYPE,
      order_id: params.orderId,
      order_number: params.orderNumber,
      order_status: params.status,
      url,
    },
  };
}

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
export async function sendOrderStatusPush(
  orderId: string,
  orderNumber: string,
  status: string
) {
  const order = await prisma.order
    .findUnique({
      where: { id: orderId },
      select: {
        userId: true,
        trackingToken: true,
        trackingNumber: true,
        courierCode: true,
        courierService: true,
        pickupCode: true,
      },
    })
    .catch(() => null);
  if (!order?.userId) return;

  const detailPath = buildOrderDetailPath(orderNumber, order.trackingToken);
  const url =
    status === "DELIVERED"
      ? appendQueryParam(detailPath, "review", "1")
      : detailPath;
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
    case "READY_FOR_PICKUP":
      body = `Pesanan kamu sudah siap diambil di Natalo Petshop / Sinar Petstore. Tunjukkan kode ${
        order.pickupCode ?? "-"
      } kepada kasir saat pickup.`;
      requireInteraction = true;
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
    case "FAILED":
    case "EXPIRED":
      body = `Batas waktu pembayaran ${orderNumber} sudah lewat. Pesanan dibatalkan otomatis — silakan pesan ulang kalau masih mau.`;
      actions = [{ action: "reorder", title: "Pesan Lagi" }];
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
    data: {
      type: ORDER_PUSH_EVENT_TYPE,
      order_id: orderId,
      order_number: orderNumber,
      order_status: status,
      url,
    },
  };

  // Kirim ke 2 channel push paralel + insert Announcement personal:
  // - Web Push (PWA Safari, Chrome Android, desktop browsers) via VAPID
  // - FCM    (Android + iOS native app) via firebase-admin — Firebase
  //   forward token iOS ke APNs Apple di baliknya. sendApnsToUser (direct
  //   APNs) SENGAJA TIDAK dipanggil bersamaan — client iOS register token
  //   FCM DAN raw APNs sekaligus utk device yang sama; memanggil dua-duanya
  //   mengirim 2 notifikasi native identik ke 1 perangkat (root cause bug
  //   "sering double notifikasi", lihat komentar lib/fcm.ts).
  // - Announcement (in-app notification center / bell icon) — targetUserId
  //   = order.userId supaya CUMA user ini yg lihat (bukan broadcast).
  //
  // Tujuan Announcement: backstop kalau user belum opt-in push — mereka
  // tetap bisa lihat update status di /notifications saat buka app.
  await Promise.all([
    sendPushToUser(order.userId, payload),
    sendFcmToUser(order.userId, payload),
    prisma.announcement
      .create({
        data: {
          title,
          body,
          url,
          segment: "all", // tidak relevan saat targetUserId set, default aja
          type: "order",
          ctaLabel: "Lihat Pesanan",
          publishedAt: new Date(),
          targetUserId: order.userId,
        },
      })
      .catch((err) => {
        // Jangan biarin gagal insert announcement merusak flow push.
        console.warn("[push] failed to create Announcement:", err);
      }),
  ]);
}

/**
 * Reminder push H-3 sebelum order auto-confirm DELIVERED.
 *
 * Dipanggil dari cron /api/cron/order-confirm-reminder yang jalan
 * harian. Goal: nudge customer untuk tap "Sudah Diterima" manual
 * supaya status DELIVERED reflect reality + (future) dapat loyalty
 * poin bonus.
 *
 * Dispatch ke 3 channel mobile-first (APNs + FCM + Announcement) +
 * Web Push. Tag "confirm-reminder-{orderId}" supaya kalau cron miss/
 * delay 1 hari dan kirim ulang, notif replace bukan stack.
 *
 * @returns true kalau push dispatched.
 */
export async function sendConfirmReminderPush(input: {
  userId: string;
  orderId: string;
  orderNumber: string;
}): Promise<boolean> {
  const title = `Pesanan #${input.orderNumber} sudah sampai?`;
  const body =
    'Tap "Sudah Diterima" di app supaya pesanan ditandai selesai. ' +
    "Otomatis selesai 3 hari lagi.";
  const url = `/member/order-detail?orderNumber=${input.orderNumber}`;

  const payload: PushPayload = {
    title,
    body,
    url,
    tag: `confirm-reminder-${input.orderId}`,
    category: "order",
    data: {
      type: "confirm_reminder",
      order_id: input.orderId,
      order_number: input.orderNumber,
    },
  };

  try {
    // 2 channel (web + FCM) — sendApnsToUser dihapus, lihat komentar
    // sendOrderStatusPush di atas (dobel notif iOS).
    await Promise.all([
      sendPushToUser(input.userId, payload),
      sendFcmToUser(input.userId, payload),
      prisma.announcement
        .create({
          data: {
            title,
            body,
            url,
            segment: "all",
            type: "order",
            ctaLabel: "Lihat Pesanan",
            publishedAt: new Date(),
            targetUserId: input.userId,
          },
        })
        .catch((err) => {
          console.warn("[push] confirm-reminder announcement:", err);
        }),
    ]);
    return true;
  } catch (err) {
    console.error("[push] confirm-reminder dispatch failed:", err);
    return false;
  }
}
