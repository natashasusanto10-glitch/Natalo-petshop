/**
 * Voucher business rules helpers — dipakai bersama oleh halaman cart &
 * checkout supaya logic seragam (lihat CLAUDE.md - Voucher business rules).
 *
 * Catatan: validasi FINAL & total tetap di backend (route handlers di
 * app/api/...). Helper ini cuma compute display & disabled-reason untuk UI.
 */

import type { Voucher } from "@prisma/client";
import { collectOrderVoucherCodes, isFreeShippingVoucher } from "@/lib/voucher-kind";

export type VoucherUsageLimitPeriodValue =
  | "NONE"
  | "LIFETIME"
  | "DAY"
  | "WEEK"
  | "MONTH";

export type VoucherUsageOrder = {
  createdAt: Date;
  voucherCode?: string | null;
  productVoucherCode?: string | null;
  shippingVoucherCode?: string | null;
  loyaltyVoucherCode?: string | null;
  manualVoucherCode?: string | null;
};

export type VoucherDisplayItem = {
  id: string;
  code: string;
  description: string | null;
  discountPercent: number | null;
  discountAmount: number | null;
  maxDiscountAmount?: number | null;
  minimumOrder: number;
  expiresAt: string | null;
  sourceType: "CUSTOMER" | "SELLER_MANUAL";
  kind: "PRODUCT_DISCOUNT" | "FREE_SHIPPING" | "LOYALTY_CLAIM" | "MANUAL_PRIVATE";
  targetUser?: "ALL_MEMBERS" | "NEW_MEMBER";
  usageLimitPeriod?: VoucherUsageLimitPeriodValue;
  /** Nilai diskon yg dihitung untuk subtotal saat ini */
  discount: number;
  /** Apakah voucher applicable untuk subtotal saat ini */
  applicable: boolean;
  /** Alasan disabled (kalau applicable=false) */
  disabledReason: string | null;
};

export type VoucherUserContext = {
  isLoggedIn: boolean;
  /** ID user — kalau guest, null. Voucher Natalo wajib login. */
  userId: string | null;
  createdAt?: Date | null;
  successfulOrderCount?: number;
};

export function calcVoucherDiscount(
  subtotal: number,
  voucher: Pick<Voucher, "discountPercent" | "discountAmount"> & {
    kind?: string | null;
    maxDiscountAmount?: number | null;
  },
): number {
  if (isFreeShippingVoucher(voucher)) return 0;
  let discount = 0;
  if (voucher.discountPercent) {
    discount += Math.floor((subtotal * voucher.discountPercent) / 100);
  }
  if (voucher.discountAmount) {
    discount += voucher.discountAmount;
  }
  if (voucher.maxDiscountAmount && voucher.maxDiscountAmount > 0) {
    discount = Math.min(discount, voucher.maxDiscountAmount);
  }
  return Math.min(discount, subtotal);
}

function getUsageWindowStart(
  period: VoucherUsageLimitPeriodValue,
  now: Date,
) {
  if (period === "LIFETIME") return null;
  const start = new Date(now);
  if (period === "DAY") {
    start.setDate(start.getDate() - 1);
    return start;
  }
  if (period === "WEEK") {
    start.setDate(start.getDate() - 7);
    return start;
  }
  if (period === "MONTH") {
    start.setMonth(start.getMonth() - 1);
    return start;
  }
  return null;
}

export function countVoucherUsageForOrders(
  voucher: Pick<Voucher, "code"> & {
    usageLimitPeriod?: VoucherUsageLimitPeriodValue | null;
  },
  userUsedOrders: VoucherUsageOrder[],
  now: Date = new Date(),
) {
  const period = voucher.usageLimitPeriod ?? "LIFETIME";
  if (period === "NONE") return 0;

  const windowStart = getUsageWindowStart(period, now);
  let count = 0;
  for (const order of userUsedOrders) {
    if (windowStart && order.createdAt < windowStart) continue;
    if (collectOrderVoucherCodes(order).includes(voucher.code)) count += 1;
  }
  return count;
}

export function isVoucherUsageLimitReached(
  voucher: Pick<Voucher, "code" | "usageLimitPerUser"> & {
    usageLimitPeriod?: VoucherUsageLimitPeriodValue | null;
  },
  userUsedOrders: VoucherUsageOrder[],
  now: Date = new Date(),
) {
  const period = voucher.usageLimitPeriod ?? "LIFETIME";
  if (period === "NONE") return false;
  const usageLimit = voucher.usageLimitPerUser ?? 1;
  if (usageLimit <= 0) return false;
  return countVoucherUsageForOrders(voucher, userUsedOrders, now) >= usageLimit;
}

export function voucherUsageLimitLabel(input: {
  usageLimitPeriod?: VoucherUsageLimitPeriodValue | null;
  usageLimitPerUser?: number | null;
}) {
  const period = input.usageLimitPeriod ?? "LIFETIME";
  const limit = input.usageLimitPerUser ?? 1;
  if (period === "NONE" || limit <= 0) return "Tanpa batas per user";
  if (period === "DAY") return `${limit}x per hari`;
  if (period === "WEEK") return `${limit}x per minggu`;
  if (period === "MONTH") return `${limit}x per bulan`;
  return "1x per user";
}

/**
 * Cek apakah voucher harus DI-FILTER OUT (tidak ditampilkan sama sekali)
 * dari daftar voucher member. Sesuai aturan UX baru:
 * - Voucher expired
 * - Voucher tidak aktif
 * - Global max usage tercapai
 * - Per-user usage limit tercapai
 *
 * Voucher yg di-filter out tidak relevan lagi — tampil cuma bikin
 * daftar berisik & user bingung.
 *
 * Param `userUsedOrders` adalah daftar order user yang punya kode voucher.
 * Periode limit (tanpa batas, lifetime, harian, mingguan, bulanan) dibaca
 * dari setting voucher.
 */
export function shouldHideVoucher(
  voucher: Pick<
    Voucher,
    | "code"
    | "isActive"
    | "expiresAt"
    | "maxUsage"
    | "usedCount"
    | "usageLimitPerUser"
    | "usageLimitPeriod"
  >,
  userUsedOrders: VoucherUsageOrder[],
  now: Date = new Date(),
): boolean {
  if (!voucher.isActive) return true;
  if (voucher.expiresAt && voucher.expiresAt <= now) return true;
  if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) return true;
  if (isVoucherUsageLimitReached(voucher, userUsedOrders, now)) return true;
  return false;
}

export function getNewMemberVoucherDisabledReason(
  voucher: Pick<
    Voucher,
    | "targetUser"
    | "newMemberMaxAccountAgeDays"
    | "newMemberRequireNoSuccessfulOrder"
  >,
  user: VoucherUserContext,
  now: Date = new Date(),
): string | null {
  if (voucher.targetUser !== "NEW_MEMBER") return null;
  if (!user.isLoggedIn || !user.createdAt) return "Login untuk menggunakan voucher member baru";

  if (
    voucher.newMemberMaxAccountAgeDays !== null &&
    voucher.newMemberMaxAccountAgeDays !== undefined &&
    voucher.newMemberMaxAccountAgeDays > 0
  ) {
    const maxAgeMs = voucher.newMemberMaxAccountAgeDays * 24 * 60 * 60 * 1000;
    const accountAgeMs = now.getTime() - user.createdAt.getTime();
    if (accountAgeMs > maxAgeMs) {
      return "Masa berlaku voucher member baru untuk akun kamu sudah berakhir.";
    }
  }

  if (voucher.newMemberRequireNoSuccessfulOrder && (user.successfulOrderCount ?? 0) > 0) {
    return "Voucher ini hanya berlaku untuk akun baru yang belum pernah melakukan checkout.";
  }

  return null;
}

/**
 * Tentukan alasan disabled UI untuk voucher yang LOLOS shouldHideVoucher
 * (artinya masih mungkin dipakai nanti).
 *
 * Return alasan disabled atau null kalau applicable.
 *
 * Hanya return alasan untuk kondisi "transient" — yg bisa berubah saat
 * cart berubah (mis. user nambah produk → memenuhi min belanja). Voucher
 * yg permanently invalid (expired, sudah dipakai) sudah di-filter di
 * shouldHideVoucher dan tidak masuk function ini.
 */
export function getVoucherDisabledReason(
  voucher: Pick<
    Voucher,
    | "minimumOrder"
    | "startsAt"
    | "targetUser"
    | "newMemberMaxAccountAgeDays"
    | "newMemberRequireNoSuccessfulOrder"
  >,
  subtotal: number,
  user: VoucherUserContext,
  now: Date = new Date(),
): string | null {
  if (!user.isLoggedIn) {
    return "Login untuk menggunakan voucher";
  }
  if (voucher.startsAt > now) {
    return "Voucher belum berlaku";
  }
  const newMemberReason = getNewMemberVoucherDisabledReason(voucher, user, now);
  if (newMemberReason) return newMemberReason;
  if (subtotal < voucher.minimumOrder) {
    return "Belum memenuhi minimum belanja";
  }
  return null;
}

/**
 * Validasi kombinasi voucher per aturan Natalo:
 * - Maks 4 voucher per checkout
 * - 1 diskon produk + 1 gratis ongkir + 1 loyalty claim + 1 manual/private
 *
 * Return error message atau null kalau valid.
 */
export function validateVoucherCombination(input: {
  selectedMemberCode: string | null;
  appliedPrivateCode: string | null;
}): string | null {
  // Implementasi multi-slot sudah secara struktural dicegah di checkout
  // backend/UI. Helper ini reserved untuk caller lama.
  return null;
}

/**
 * Hitung total diskon dari kombinasi voucher lama (member + private), capped at
 * subtotal supaya tidak negative.
 */
export function calculateFinalDiscount(input: {
  subtotal: number;
  memberDiscount: number;
  privateDiscount: number;
}): number {
  return Math.min(input.memberDiscount + input.privateDiscount, input.subtotal);
}
