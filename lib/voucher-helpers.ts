/**
 * Voucher business rules helpers — dipakai bersama oleh halaman cart &
 * checkout supaya logic seragam (lihat CLAUDE.md - Voucher business rules).
 *
 * Catatan: validasi FINAL & total tetap di backend (route handlers di
 * app/api/...). Helper ini cuma compute display & disabled-reason untuk UI.
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
    "code" | "isActive" | "expiresAt" | "maxUsage" | "usedCount"
  >,
  userUsedCodes: Set<string>,
  now: Date = new Date(),
): boolean {
  if (!voucher.isActive) return true;
  if (voucher.expiresAt && voucher.expiresAt <= now) return true;
  if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) return true;
  if (userUsedCodes.has(voucher.code)) return true;
  return false;
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
  voucher: Pick<Voucher, "minimumOrder" | "startsAt">,
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
