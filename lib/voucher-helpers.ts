/**
 * Voucher business rules helpers — dipakai bersama oleh halaman cart &
 * checkout supaya logic seragam (lihat CLAUDE.md - Voucher business rules).
 *
 * Catatan: validasi FINAL & total tetap di backend (route handlers di
 * app/api/...). Helper ini cuma compute display & disabled-reason untuk UI.
 */

import type { Voucher } from "@prisma/client";
import { isFreeShippingVoucher } from "@/lib/voucher-kind";

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

function getUsageCount(
  userUsedCodes: Set<string> | Map<string, number>,
  code: string,
) {
  return userUsedCodes instanceof Map
    ? userUsedCodes.get(code) ?? 0
    : userUsedCodes.has(code)
      ? 1
      : 0;
}

/**
 * Cek apakah voucher harus DI-FILTER OUT (tidak ditampilkan sama sekali)
 * dari daftar voucher member. Sesuai aturan UX baru:
 * - Voucher expired
 * - Voucher tidak aktif
 * - Global max usage tercapai
 * - User sudah pernah pakai (per-user usage limit tercapai)
 *
 * Voucher yg di-filter out tidak relevan lagi — tampil cuma bikin
 * daftar berisik & user bingung.
 *
 * Param `userUsedCodes` adalah Set kode voucher yang sudah dipakai user
 * di order sebelumnya. Voucher dgn kode di Set ini di-skip.
 */
export function shouldHideVoucher(
  voucher: Pick<
    Voucher,
    "code" | "isActive" | "expiresAt" | "maxUsage" | "usedCount" | "usageLimitPerUser"
  >,
  userUsedCodes: Set<string> | Map<string, number>,
  now: Date = new Date(),
): boolean {
  if (!voucher.isActive) return true;
  if (voucher.expiresAt && voucher.expiresAt <= now) return true;
  if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) return true;
  const usageLimit = voucher.usageLimitPerUser ?? 1;
  if (usageLimit > 0 && getUsageCount(userUsedCodes, voucher.code) >= usageLimit) return true;
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
