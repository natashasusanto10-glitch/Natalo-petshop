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
  freeShippingVoucherCode?: string | null;
  productVoucherCode?: string | null;
  shippingVoucherCode?: string | null;
  loyaltyVoucherCode?: string | null;
  manualVoucherCode?: string | null;
  privateVoucherCode?: string | null;
};

export type VoucherTypeCode =
  | "PUBLIC_FREE_SHIPPING"
  | "PUBLIC_PRODUCT_DISCOUNT"
  | "LOYALTY_POINT_CLAIM"
  | "PRIVATE_MANUAL_CODE";

export type VoucherVisibilityCode = "PUBLIC" | "PRIVATE" | "USER_OWNED";
export type VoucherDiscountScopeCode = "PRODUCT" | "SHIPPING";

export type VoucherDisplayItem = {
  id: string;
  name: string | null;
  code: string;
  description: string | null;
  discountPercent: number | null;
  discountAmount: number | null;
  maxDiscountAmount: number | null;
  minimumOrder: number;
  expiresAt: string | null;
  sourceType: "CUSTOMER" | "SELLER_MANUAL";
  type: VoucherTypeCode;
  visibility: VoucherVisibilityCode;
  discountScope: VoucherDiscountScopeCode;
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
  voucher: Pick<
    Voucher,
    "discountPercent" | "discountAmount" | "maxDiscountAmount" | "kind"
  >,
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

export function voucherTypeOf(
  voucher: Pick<Voucher, "type" | "sourceType" | "userId">,
): VoucherTypeCode {
  if (voucher.type) return voucher.type as VoucherTypeCode;
  if (voucher.sourceType === "SELLER_MANUAL") return "PRIVATE_MANUAL_CODE";
  if (voucher.userId) return "LOYALTY_POINT_CLAIM";
  return "PUBLIC_PRODUCT_DISCOUNT";
}

export function voucherVisibilityOf(
  voucher: Pick<Voucher, "visibility" | "sourceType" | "userId">,
): VoucherVisibilityCode {
  if (voucher.visibility) return voucher.visibility as VoucherVisibilityCode;
  if (voucher.sourceType === "SELLER_MANUAL") return "PRIVATE";
  if (voucher.userId) return "USER_OWNED";
  return "PUBLIC";
}

export function voucherScopeOf(
  voucher: Pick<Voucher, "discountScope" | "type">,
): VoucherDiscountScopeCode {
  if (voucher.discountScope) return voucher.discountScope as VoucherDiscountScopeCode;
  return voucher.type === "PUBLIC_FREE_SHIPPING" ? "SHIPPING" : "PRODUCT";
}

export function calcVoucherScopedDiscount(input: {
  subtotal: number;
  shippingFee: number;
  eligibleProductSubtotal?: number;
  voucher: Pick<
    Voucher,
    | "discountPercent"
    | "discountAmount"
    | "maxDiscountAmount"
    | "discountScope"
    | "type"
    | "kind"
  >;
}) {
  const scope = voucherScopeOf(input.voucher);
  const base =
    scope === "SHIPPING"
      ? input.shippingFee
      : input.eligibleProductSubtotal ?? input.subtotal;
  if (scope === "SHIPPING") {
    const shippingBase = Math.max(0, base);
    if (shippingBase <= 0) return 0;

    let discount = 0;
    if (input.voucher.discountPercent) {
      discount += Math.floor((shippingBase * input.voucher.discountPercent) / 100);
    }
    if (input.voucher.discountAmount) {
      discount += input.voucher.discountAmount;
    }
    if (isFreeShippingVoucher(input.voucher) && discount <= 0) {
      discount = shippingBase;
    }
    if (input.voucher.maxDiscountAmount && input.voucher.maxDiscountAmount > 0) {
      discount = Math.min(discount, input.voucher.maxDiscountAmount);
    }
    return Math.min(discount, shippingBase);
  }

  return calcVoucherDiscount(Math.max(0, base), input.voucher);
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

/**
 * Cek apakah user sudah mencapai limit pemakaian voucher dalam periode.
 *
 * Berdasarkan `usageLimitPerUser` (jumlah max) + `usageLimitPeriod` (window):
 * - NONE: no limit, selalu return false (boleh terus pakai)
 * - LIFETIME: count semua order pakai voucher ini ever
 * - DAY: count order 24 jam terakhir
 * - WEEK: count order 7 hari terakhir
 * - MONTH: count order 30 hari terakhir
 *
 * Return true kalau user **sudah reach limit** (tidak boleh pakai lagi).
 *
 * Dipakai di:
 * - lib/product-vouchers.ts (filter eligible vouchers)
 * - app/api/cart/vouchers/validate-private/route.ts
 * - app/api/member/vouchers/route.ts
 */
export function isVoucherUsageLimitReached(
  voucher: {
    code?: string | null;
    usageLimitPerUser?: number | null;
    usageLimitPeriod?: VoucherUsageLimitPeriodValue | null;
  },
  userUsedOrders: VoucherUsageOrder[],
  now: Date = new Date(),
): boolean {
  const limit = voucher.usageLimitPerUser ?? 1;
  const period = voucher.usageLimitPeriod ?? "LIFETIME";

  if (period === "NONE" || limit <= 0) return false;
  const code = voucher.code?.trim().toUpperCase();
  if (!code) return false;

  // Hitung cutoff timestamp untuk count orders dalam window.
  let cutoff: Date | null = null;
  if (period === "DAY") {
    cutoff = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  } else if (period === "WEEK") {
    cutoff = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  } else if (period === "MONTH") {
    cutoff = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  }
  // LIFETIME → cutoff null → count semua

  const ordersWithThisVoucher = userUsedOrders.filter((order) =>
    collectOrderVoucherCodes(order).some(
      (usedCode) => usedCode.trim().toUpperCase() === code,
    ),
  );
  const cutoffMs = cutoff?.getTime();
  const ordersInPeriod = cutoffMs !== undefined
    ? ordersWithThisVoucher.filter((o) => o.createdAt.getTime() >= cutoffMs)
    : ordersWithThisVoucher;

  return ordersInPeriod.length >= limit;
}

/**
 * Format display label untuk limit pemakaian voucher per user.
 * Combine `usageLimitPerUser` count + `usageLimitPeriod` periode.
 *
 * Contoh output:
 * - 0 / NONE → "Tanpa batas"
 * - 1 / LIFETIME → "1× selamanya"
 * - 3 / DAY → "3× per hari"
 * - 1 / MONTH → "1× per bulan"
 *
 * Dipakai di admin voucher listing page untuk show ringkas user-facing
 * label tanpa expose internal enum value.
 */
export function voucherUsageLimitLabel(v: {
  usageLimitPerUser?: number | null;
  usageLimitPeriod?: VoucherUsageLimitPeriodValue | null;
}): string {
  const count = v.usageLimitPerUser ?? 1;
  const period = v.usageLimitPeriod ?? "LIFETIME";

  if (period === "NONE" || count === 0) return "Tanpa batas";

  const periodLabel: Record<VoucherUsageLimitPeriodValue, string> = {
    NONE: "",
    LIFETIME: "selamanya",
    DAY: "per hari",
    WEEK: "per minggu",
    MONTH: "per bulan",
  };

  return `${count}× ${periodLabel[period]}`.trim();
}
