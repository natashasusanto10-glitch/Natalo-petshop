/**
 * Push notification helpers untuk ADMIN users.
 *
 * Pattern: cari semua user dengan role=ADMIN yang punya FCM token aktif,
 * lalu kirim notif ke semua device mereka. Multi-admin support — owner
 * + staff sama-sama dapat.
 *
 * Trigger points:
 *   - Order baru (status PENDING) — `sendAdminOrderNewPush()`
 *   - Cancellation request masuk — `sendAdminCancellationRequestPush()`
 *   - Feed customer post PENDING_REVIEW — `sendAdminFeedPendingPush()`
 *   - Abuse flag HIGH severity — `sendAdminAbuseFlagPush()`
 *
 * WAJIB di-await (atau dibungkus `after()` dari next/server) oleh caller —
 * Vercel membekukan function begitu response terkirim, jadi promise yang
 * di-`void` bisa tak pernah jalan (lihat lib/feed/reconcile.ts). Aman
 * di-await: semua error delivery ditelan internal (allSettled + catch),
 * tidak pernah menggagalkan event utama (create order, dll).
 */
import { prisma } from "@/lib/prisma";
import { sendFcmToUser } from "@/lib/fcm";

type AdminPushPayload = {
  title: string;
  body: string;
  /** Deep-link path untuk navigasi saat admin tap notif. */
  url?: string;
  /** Tag untuk dedup di Android (newer notif dgn tag yang sama replace older). */
  tag?: string;
  data?: Record<string, string>;
};

async function getAdminUserIds(): Promise<string[]> {
  const admins = await prisma.user
    .findMany({
      where: { role: "ADMIN" },
      select: { id: true },
    })
    .catch(() => []);
  return admins.map((a) => a.id);
}

async function sendToAllAdmins(payload: AdminPushPayload) {
  const adminIds = await getAdminUserIds();
  if (adminIds.length === 0) return;
  // Paralel, tidak boleh fail kalau satu admin tokennya invalid.
  await Promise.allSettled(
    adminIds.map((id) =>
      sendFcmToUser(id, payload).catch((err) => {
        console.warn("[push-admin] send to", id, "failed:", err);
      }),
    ),
  );
}

export async function sendAdminOrderNewPush(args: {
  orderNumber: string;
  customerName: string;
  total: number;
}): Promise<void> {
  await sendToAllAdmins({
    title: '🛒 Order baru!',
    body: `${args.customerName} — ${formatRp(args.total)} (${args.orderNumber})`,
    url: `/admin/orders/${args.orderNumber}`,
    tag: `order-new-${args.orderNumber}`,
    data: {
      type: 'ORDER_NEW',
      orderNumber: args.orderNumber,
    },
  });
}

export async function sendAdminCancellationRequestPush(args: {
  orderNumber: string;
  customerName: string;
  reason: string | null;
}): Promise<void> {
  await sendToAllAdmins({
    title: '⚠️ Permintaan pembatalan',
    body: `${args.customerName} minta cancel ${args.orderNumber}${
      args.reason ? ' — ' + truncate(args.reason, 60) : ''
    }`,
    url: `/admin/orders/${args.orderNumber}`,
    tag: `cancel-req-${args.orderNumber}`,
    data: {
      type: 'CANCEL_REQUEST',
      orderNumber: args.orderNumber,
    },
  });
}

export async function sendAdminFeedPendingPush(args: {
  postId: string;
  authorName: string;
  title: string;
}): Promise<void> {
  await sendToAllAdmins({
    title: '📸 Post komunitas baru',
    body: `${args.authorName}: ${truncate(args.title, 60)}`,
    url: `/admin/feed/${args.postId}`,
    tag: `feed-pending-${args.postId}`,
    data: {
      type: 'FEED_PENDING',
      postId: args.postId,
    },
  });
}

export async function sendAdminAbuseFlagPush(args: {
  flagId: string;
  ruleCode: string;
  severity: string;
  userName: string;
}): Promise<void> {
  // Hanya untuk HIGH severity supaya admin tidak terganggu noise.
  if (args.severity !== 'HIGH') return;
  await sendToAllAdmins({
    title: '🚨 Abuse flag baru',
    body: `${args.userName} — ${args.ruleCode}`,
    url: `/admin/abuse-flags`,
    tag: `abuse-${args.flagId}`,
    data: {
      type: 'ABUSE_FLAG',
      flagId: args.flagId,
    },
  });
}

function formatRp(n: number): string {
  return `Rp${new Intl.NumberFormat('id-ID').format(Math.round(n))}`;
}

function truncate(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, max - 1) + '…';
}
