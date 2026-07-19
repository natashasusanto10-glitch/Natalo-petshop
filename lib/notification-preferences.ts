import { prisma } from "@/lib/prisma";

/**
 * Push notification preferences — single source of truth untuk kategori
 * toggle yang dipakai bersama oleh:
 *   - Flutter NotificationPreferencesScreen (key harus identik)
 *   - GET/PUT /api/member/notification-preferences
 *   - Server-side dispatch filter (sendPushToUser / sendFcmToUser)
 *
 * Kenapa server-side filter: client-side filter Flutter cuma jalan untuk
 * pesan foreground yang punya `data.category`, sementara notifikasi tray/
 * background ditampilkan langsung oleh OS/FCM tanpa lewat app. Jadi satu-
 * satunya cara toggle benar-benar menghentikan notif adalah memfilter
 * SEBELUM dispatch di server.
 */

export type NotificationCategory =
  | "master"
  | "order"
  | "promo"
  | "voucher"
  | "product"
  | "loyalty_points"
  | "chat"
  | "feed";

export const NOTIFICATION_CATEGORIES: NotificationCategory[] = [
  "master",
  "order",
  "promo",
  "voucher",
  "product",
  "loyalty_points",
  "chat",
  "feed",
];

/**
 * Default preferensi — identik dengan default Flutter screen. `master` ON =
 * user menerima notif sesuai per-kategori. `product` & `feed` default OFF
 * (opt-in), sisanya ON.
 */
export const DEFAULT_NOTIFICATION_PREFS: Record<NotificationCategory, boolean> =
  {
    master: true,
    order: true,
    promo: true,
    voucher: true,
    product: false,
    loyalty_points: true,
    chat: true,
    feed: false,
  };

/**
 * Normalisasi raw JSON (unknown shape dari DB/body) → map lengkap yang
 * terisi default untuk key yang hilang. Non-bool / key asing dibuang.
 */
export function normalizeNotificationPrefs(
  raw: unknown,
): Record<NotificationCategory, boolean> {
  const result = { ...DEFAULT_NOTIFICATION_PREFS };
  if (raw && typeof raw === "object") {
    for (const cat of NOTIFICATION_CATEGORIES) {
      const value = (raw as Record<string, unknown>)[cat];
      if (typeof value === "boolean") result[cat] = value;
    }
  }
  return result;
}

/**
 * Ambil preferensi tersimpan seorang user (default kalau belum pernah set
 * atau query gagal — fail-open supaya notif penting tidak ikut hilang saat
 * DB error).
 */
export async function getUserNotificationPrefs(
  userId: string,
): Promise<Record<NotificationCategory, boolean>> {
  try {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { notificationPrefs: true },
    });
    return normalizeNotificationPrefs(user?.notificationPrefs);
  } catch {
    return { ...DEFAULT_NOTIFICATION_PREFS };
  }
}

/**
 * Apakah kategori push ini enabled untuk user? Master OFF me-mute semua
 * kategori (kecuali caller memang tidak set prefCategory = notif kritikal
 * seperti keamanan yang bypass filter). Fail-open on error.
 */
export async function isPushCategoryEnabled(
  userId: string,
  category: NotificationCategory,
): Promise<boolean> {
  const prefs = await getUserNotificationPrefs(userId);
  if (!prefs.master) return false;
  return prefs[category] ?? true;
}
