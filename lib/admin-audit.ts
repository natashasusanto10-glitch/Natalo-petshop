/**
 * Audit log helper untuk admin actions.
 *
 * Pattern: fire-and-forget — logging failure tidak boleh block admin
 * action. Catch error + console.warn supaya kelihatan di log Vercel
 * tanpa nge-throw upstream.
 *
 * Usage:
 *   await logAdminAction({
 *     actorUserId: session.sub,
 *     action: "REFUND_ISSUED",
 *     targetType: "Order",
 *     targetId: orderId,
 *     summary: `Refund Rp${amount} untuk order #${orderNumber}`,
 *     metadata: { amount, reason, itemId },
 *   });
 *
 * Atau pakai `recordAdminAction()` yang awaited untuk critical path
 * (e.g. compliance-mandatory action). Default: fire-and-forget via
 * `logAdminAction()`.
 */
import { prisma } from "@/lib/prisma";

/**
 * Konstanta action codes — gunakan ini biar konsisten antar callsite.
 * Tambah baru sesuai kebutuhan, jangan inline string.
 */
export const AdminAction = {
  // Order lifecycle
  ORDER_MARK_PAID: "ORDER_MARK_PAID",
  ORDER_MARK_PROCESSING: "ORDER_MARK_PROCESSING",
  ORDER_MARK_READY_PICKUP: "ORDER_MARK_READY_PICKUP",
  ORDER_MARK_PICKED_UP: "ORDER_MARK_PICKED_UP",
  ORDER_MARK_SHIPPED: "ORDER_MARK_SHIPPED",
  ORDER_MARK_DELIVERED: "ORDER_MARK_DELIVERED",
  ORDER_CANCELLED: "ORDER_CANCELLED",
  ORDER_CANCEL_REQUEST_APPROVED: "ORDER_CANCEL_REQUEST_APPROVED",
  ORDER_CANCEL_REQUEST_REJECTED: "ORDER_CANCEL_REQUEST_REJECTED",
  ORDER_SHIPMENT_CREATED: "ORDER_SHIPMENT_CREATED",
  // Refund
  REFUND_ISSUED: "REFUND_ISSUED",
  REFUND_ITEM_OOS: "REFUND_ITEM_OOS",
  // Voucher
  VOUCHER_CREATED: "VOUCHER_CREATED",
  VOUCHER_UPDATED: "VOUCHER_UPDATED",
  VOUCHER_DELETED: "VOUCHER_DELETED",
  // User management
  USER_ROLE_CHANGED: "USER_ROLE_CHANGED",
  USER_DELETED: "USER_DELETED",
  // Feed moderation
  FEED_POST_APPROVED: "FEED_POST_APPROVED",
  FEED_POST_REJECTED: "FEED_POST_REJECTED",
  FEED_POST_HIDDEN: "FEED_POST_HIDDEN",
  FEED_COMMENT_HIDDEN: "FEED_COMMENT_HIDDEN",
  // Push broadcast
  PUSH_BROADCAST: "PUSH_BROADCAST",
} as const;

export type AdminActionType = (typeof AdminAction)[keyof typeof AdminAction];

export type AdminAuditParams = {
  actorUserId: string;
  action: AdminActionType | string;
  targetType: string;
  targetId: string;
  summary: string;
  metadata?: Record<string, unknown>;
  ipAddress?: string | null;
};

/**
 * Fire-and-forget logging. Tidak block caller — error di-swallow +
 * console.warn. Pakai ini di mayoritas admin action.
 */
export function logAdminAction(params: AdminAuditParams): void {
  void recordAdminAction(params).catch((err) => {
    console.warn("[admin-audit] log failed:", {
      action: params.action,
      targetId: params.targetId,
      error: err instanceof Error ? err.message : String(err),
    });
  });
}

/**
 * Awaited version — pakai untuk compliance-mandatory action yang
 * butuh konfirmasi log tersimpan sebelum response success. Throw
 * kalau write gagal. Use sparingly — fire-and-forget cukup untuk
 * 99% kasus.
 */
export async function recordAdminAction(
  params: AdminAuditParams,
): Promise<void> {
  await prisma.adminActionLog.create({
    data: {
      actorUserId: params.actorUserId,
      action: params.action,
      targetType: params.targetType,
      targetId: params.targetId,
      summary: params.summary,
      metadata: params.metadata
        ? (params.metadata as object)
        : undefined,
      ipAddress: params.ipAddress ?? null,
    },
  });
}

/**
 * Helper buat extract IP address dari request headers. Vercel proxy
 * pass via X-Forwarded-For atau X-Real-IP. Pakai di server action
 * yang butuh capture IP (e.g. user-impacting action). Server action
 * context tidak punya akses langsung ke `request`, jadi opsional —
 * mostly null. Untuk full IP audit gunakan API route biasa.
 */
export function ipFromHeaders(headers: Headers | Record<string, string>): string | null {
  const get = (key: string): string | undefined => {
    if (headers instanceof Headers) return headers.get(key) ?? undefined;
    return (headers as Record<string, string>)[key];
  };
  const xff = get("x-forwarded-for");
  if (xff) return xff.split(",")[0].trim();
  return get("x-real-ip") ?? null;
}
