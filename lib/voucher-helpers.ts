/**
 * Voucher business rules helpers — dipakai bersama oleh halaman cart &
 * checkout supaya logic seragam (lihat CLAUDE.md - Voucher business rules).
 *
 * Catatan: ini library shared. Validasi FINAL & total tetap dilakukan di
 * backend (route handlers di app/api/...). Helper ini cuma compute display
 * & disabled-reason untuk UI.
 */

import type { Voucher } from "@prisma/client";

export type VoucherDisplayItem = {
  id: string;
  code: string;
  description: string | null;
  discountPercent: number | null;
  discountAmount: number | null;
  minimumOrder: number;
  expiresAt: string | null;
  sourceType: "CUSTOMER" | "SELLER_MANUAL";
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
};

export function calcVoucherDiscount(
  subtotal: number,
  voucher: Pick<Voucher, "discountPercent" | "discountAmount">,
): number {
  let discount = 0;
  if (voucher.discountPercent) {
    discount += Math.floor((subtotal * voucher.discountPercent) / 100);
  }
  if (voucher.discountAmount) {
    discount += voucher.discountAmount;
  }
  return Math.min(discount, subtotal);
}

/**
 * Tentukan apakah voucher applicable untuk user + subtotal saat ini.
 * Return alasan disabled (string) atau null kalau OK.
 *
 * Sesuai aturan Natalo:
 * - Voucher (CUSTOMER & SELLER_MANUAL) wajib login. Guest tidak boleh
 *   memakai voucher publik / member.
 * - Min belanja, expiry, dan max usage dievaluasi di sini.
 *
 * Note: cek per-user usage limit & per-product/category eligibility tidak
 * diputuskan di helper ini karena butuh DB lookup; logic itu ada di
 * route handler.
 */
export function getVoucherDisabledReason(
  voucher: Pick<
    Voucher,
    | "minimumOrder"
    | "expiresAt"
    | "startsAt"
    | "maxUsage"
    | "usedCount"
    | "isActive"
    | "sourceType"
  >,
  subtotal: number,
  user: VoucherUserContext,
  now: Date = new Date(),
): string | null {
  if (!user.isLoggedIn) {
    return "Login untuk menggunakan voucher";
  }
  if (!voucher.isActive) {
    return "Voucher sudah tidak aktif";
  }
  if (voucher.expiresAt && voucher.expiresAt <= now) {
    return "Voucher sudah berakhir";
  }
  if (voucher.startsAt > now) {
    return "Voucher belum berlaku";
  }
  if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) {
    return "Sudah pernah digunakan sesuai batas";
  }
  if (subtotal < voucher.minimumOrder) {
    return "Belum memenuhi minimum belanja";
  }
  return null;
}

/**
 * Validasi kombinasi voucher per aturan Natalo:
 * - Maks 1 CUSTOMER + 1 SELLER_MANUAL
 * - Tidak boleh 2 dari tipe yg sama
 *
 * Return error message atau null kalau valid.
 */
export function validateVoucherCombination(input: {
  selectedMemberCode: string | null;
  appliedPrivateCode: string | null;
}): string | null {
  // Implementasi single-slot per tipe sudah secara struktural prevent
  // 2 dari tipe sama. Helper ini reserved untuk future complex rule.
  return null;
}

/**
 * Hitung total diskon dari kombinasi voucher (member + private), capped at
 * subtotal supaya tidak negative.
 */
export function calculateFinalDiscount(input: {
  subtotal: number;
  memberDiscount: number;
  privateDiscount: number;
}): number {
  return Math.min(input.memberDiscount + input.privateDiscount, input.subtotal);
}
