/**
 * Push notifications untuk Refund Wallet events.
 *
 * Dispatch ke FCM (Android+iOS, Firebase forward ke APNs Apple) pakai
 * pattern yang sama dengan push-marketing.ts — sendApnsToUser (direct
 * APNs) SENGAJA tidak dipanggil bersamaan, lihat komentar lib/fcm.ts
 * (dobel notif iOS). Plus create Announcement row untuk notification
 * center in-app history.
 *
 * Trigger:
 *  - `sendRefundIssuedPush()` — saat admin issue refund + credit wallet.
 *    Dipanggil dari app/admin/(protected)/orders/[id]/actions.ts setelah
 *    RefundCase status → CREDITED. Fire-and-forget (jangan block admin
 *    action).
 *
 * Skipped events (low value / noisy):
 *  - DEBIT (user pakai saldo di checkout) — user already aware, skip notif
 *  - REVERSAL (order cancel, saldo balik) — future event, defer
 */
import { prisma } from "./prisma";
import { sendFcmToUser } from "./fcm";
import type { PushPayload } from "./push";

const REFUND_TAG_PREFIX = "refund-credited-";

const REASON_LABEL: Record<string, string> = {
  OUT_OF_STOCK: "Produk kosong",
  PARTIAL_CANCEL: "Pesanan dibatalkan sebagian",
  RETURN_APPROVED: "Return disetujui",
  ORDER_CANCELLED: "Pesanan dibatalkan",
  OTHER: "Refund",
};

function formatRupiahShort(value: number): string {
  if (value >= 1_000_000) {
    const m = value / 1_000_000;
    const fixed = m >= 10 ? m.toFixed(0) : m.toFixed(1);
    return `Rp${fixed.replace(".", ",").replace(",0", "")}jt`;
  }
  if (value >= 1000) {
    const k = value / 1000;
    const fixed = k >= 10 ? k.toFixed(0) : k.toFixed(1);
    return `Rp${fixed.replace(".", ",").replace(",0", "")}rb`;
  }
  return `Rp${value.toLocaleString("id-ID")}`;
}

/**
 * Send notification saat admin credit saldo refund ke user.
 *
 * Body example: "Refund Rp32rb sudah masuk. Whiskas Tuna 1kg sedang kosong."
 *
 * Tap notif → deep link ke `/member/refund-detail` dengan caseId arg.
 * Flutter handle via `app_links` listener (existing infrastructure).
 *
 * @returns true kalau push dispatched (Announcement created), false otherwise.
 */
export async function sendRefundIssuedPush(input: {
  userId: string;
  caseId: string;
  amount: number;
  reason: string;
  itemName?: string | null;
  adminNote?: string | null;
}): Promise<boolean> {
  const reasonLabel = REASON_LABEL[input.reason] ?? "Refund";
  const itemFragment = input.itemName
    ? ` ${input.itemName}`
    : "";
  const noteFragment = input.adminNote
    ? ` "${input.adminNote.slice(0, 80)}${input.adminNote.length > 80 ? "..." : ""}"`
    : "";

  const title = `💰 Refund ${formatRupiahShort(input.amount)} sudah masuk`;
  const body = input.itemName
    ? `${reasonLabel} —${itemFragment}.${noteFragment}`
    : `${reasonLabel}.${noteFragment}`;

  // Deep link URL — Flutter app_links handler parse path + arg
  // (caseId via query param). Fallback web: open halaman saldo.
  const url = `/member/refund-detail?caseId=${input.caseId}`;

  const payload: PushPayload = {
    title,
    body,
    url,
    // Tag per case — kalau admin re-issue / update (rare), notif replace
    // bukan stack. Cap di-prefix untuk avoid collision dengan other types.
    tag: `${REFUND_TAG_PREFIX}${input.caseId}`,
    category: "refund",
    data: {
      type: "refund_credited",
      caseId: input.caseId,
      amount: String(input.amount),
      reason: input.reason,
    },
  };

  try {
    // CHANNEL POLICY untuk refund notifications:
    //  ✅ FCM (Android+iOS native) → refund is mobile-specific (saldo lives
    //                               in app); FCM forward iOS via APNs Apple
    //  ✅ Announcement (in-app)    → notification center di Flutter app
    //  ❌ Web Push (browser)       → SKIP per user request — refund flow
    //                               fokus di mobile app, web push terlalu
    //                               noisy untuk transaksi keuangan customer
    //  ❌ sendApnsToUser (direct)  → dihapus, dobel dgn FCM utk device iOS
    //                               yang sama (lihat komentar lib/fcm.ts)
    //
    // `sendPushToUser` di-remove dari dispatch list. Web user yang akses
    // /pesanan via browser tetap bisa lihat refund di halaman saldo refund
    // (data ada), cuma tidak dapat push notif real-time.
    await Promise.all([
      sendFcmToUser(input.userId, payload),
      // Save ke notification center (Announcement model) — supaya
      // user yang tidak punya push subscription (atau push gagal)
      // tetap aware via in-app notification list.
      prisma.announcement
        .create({
          data: {
            title,
            body,
            url,
            segment: "all",
            type: "info",
            ctaLabel: "Lihat Detail",
            publishedAt: new Date(),
            targetUserId: input.userId,
          },
        })
        .catch((err) => {
          console.warn("[push-refund] announcement create:", err);
        }),
    ]);
    return true;
  } catch (err) {
    console.error("[push-refund] dispatch failed:", err);
    return false;
  }
}

const CANCEL_REJECT_TAG_PREFIX = "cancel-rejected-";

/**
 * Send notification ke customer saat admin REJECT permintaan pembatalan
 * pesanan. User lihat alasan langsung di push body — gak perlu buka app
 * untuk tahu kenapa cancel-nya ditolak.
 *
 * Trigger: dipanggil (di-await — void promise bisa dibekukan Vercel
 * sebelum jalan) dari rejectCancellationRequest server action di
 * app/admin/(protected)/orders/[id]/actions.ts setelah status di-set
 * REJECTED. Never-throw: push service down tidak mem-block admin action.
 *
 * Tap notif → deep link ke order detail supaya user bisa lihat reject
 * reason lengkap di banner (kalau push body terpotong).
 *
 * @returns true kalau push dispatched.
 */
export async function sendCancellationRejectedPush(input: {
  userId: string;
  orderId: string;
  orderNumber: string;
  rejectReason: string;
}): Promise<boolean> {
  const title = `Permintaan pembatalan #${input.orderNumber} ditolak`;
  // Cap body 120 char supaya tidak overflow push notif limit, append
  // "..." kalau truncated. Full reason tetap accessible di app banner.
  const reasonTrimmed =
    input.rejectReason.length > 120
      ? `${input.rejectReason.slice(0, 117)}...`
      : input.rejectReason;
  const body = `Alasan: "${reasonTrimmed}"`;

  // Deep link ke order detail — Flutter app_links handler buka order
  // detail screen, user lihat banner reject lengkap dengan reason.
  const url = `/member/order-detail?orderNumber=${input.orderNumber}`;

  const payload: PushPayload = {
    title,
    body,
    url,
    tag: `${CANCEL_REJECT_TAG_PREFIX}${input.orderId}`,
    category: "order",
    data: {
      type: "cancellation_rejected",
      orderId: input.orderId,
      orderNumber: input.orderNumber,
    },
  };

  try {
    // sendApnsToUser (direct APNs) dihapus — dobel dgn FCM (lihat
    // komentar lib/fcm.ts).
    await Promise.all([
      sendFcmToUser(input.userId, payload),
      // Notification center entry untuk audit + in-app history.
      prisma.announcement
        .create({
          data: {
            title,
            body,
            url,
            segment: "all",
            type: "warning",
            ctaLabel: "Lihat Pesanan",
            publishedAt: new Date(),
            targetUserId: input.userId,
          },
        })
        .catch((err) => {
          console.warn("[push-refund] cancel-reject announcement:", err);
        }),
    ]);
    return true;
  } catch (err) {
    console.error("[push-refund] cancel-reject dispatch failed:", err);
    return false;
  }
}
