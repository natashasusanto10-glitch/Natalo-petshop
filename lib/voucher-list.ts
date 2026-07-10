/**
 * Single source of truth untuk listing voucher CUSTOMER ke user.
 *
 * Dipakai oleh:
 *  - GET /api/cart/vouchers           (voucher picker di cart/checkout)
 *  - GET /api/member/vouchers         (halaman "Voucher" di Tab Transaksi)
 *
 * Tujuan helper ini: hindari drift antar endpoint yang dulu jadi
 * sumber bug (endpoint member filter `userId: session.sub` saja,
 * sedangkan endpoint cart filter `userId: null | session.sub` — voucher
 * publik admin tidak muncul di endpoint member).
 *
 * Aturan visibility (single rule untuk semua endpoint):
 *   - HIDDEN sama sekali kalau:
 *     - isActive: false
 *     - expired
 *     - global max usage tercapai
 *     - user sudah pakai sebanyak per-user limit
 *     - voucher punya eligibleUserIds[] whitelist dan user TIDAK di list
 *
 *   - Tampil dengan `applicable: false` + reason kalau:
 *     - belum login (defensive — helper ini wajib login)
 *     - voucher belum mulai (startsAt > now) → "Berlaku mulai DD/MM"
 *     - targetUser=NEW_MEMBER tapi user lama → "Hanya untuk akun baru..."
 *     - subtotal < minimumOrder → "Belanja Rp X lagi"
 *
 *   - `hasProductScope: true` kalau voucher punya eligibleProductIds[]
 *     atau eligibleCategoryIds[] — UI bisa render label "Berlaku untuk
 *     produk tertentu". Real scope check tetap di checkout/recalculate
 *     karena listing tidak punya cart items context (subtotal saja).
 */

import type { Voucher } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import {
  calcVoucherDiscount,
  getVoucherDisabledReason,
  shouldHideVoucher,
  voucherScopeOf,
  voucherTypeOf,
  voucherVisibilityOf,
  type VoucherDiscountScopeCode,
  type VoucherTypeCode,
  type VoucherUsageOrder,
  type VoucherUserContext,
  type VoucherVisibilityCode,
} from "@/lib/voucher-helpers";
import { isFreeShippingVoucher } from "@/lib/voucher-kind";
import {
  cartMatchesVoucherScope,
  voucherHasScope,
  formatVoucherBrandName,
  loadBrandNamesByIds,
  type EligibilityProductInput,
} from "@/lib/voucher-eligibility";

export type VoucherListItem = {
  id: string;
  name: string | null;
  code: string;
  description: string | null;
  discountPercent: number | null;
  discountAmount: number | null;
  maxDiscountAmount: number | null;
  minimumOrder: number;
  expiresAt: Date | null;
  sourceType: "CUSTOMER" | "SELLER_MANUAL";
  type: VoucherTypeCode;
  visibility: VoucherVisibilityCode;
  discountScope: VoucherDiscountScopeCode;
  /** Nilai diskon untuk subtotal — 0 kalau not applicable atau free shipping. */
  discount: number;
  /** True kalau bisa dipakai sekarang (no disabled reason). */
  applicable: boolean;
  /** Alasan disabled (kalau applicable=false). */
  disabledReason: string | null;
  /**
   * True kalau voucher punya eligibleProductIds[] atau eligibleCategoryIds[]
   * non-empty. Real scope check di checkout/recalculate — listing tidak
   * cek per-cart-item.
   */
  hasProductScope: boolean;
  /** Nama brand untuk display ("Khusus {brand}") -- null kalau voucher tidak scoped ke brand manapun. */
  brandName: string | null;
};

export type ListUserVouchersResult = {
  items: VoucherListItem[];
};

export type ListUserVouchersParams = {
  /** Required — voucher Natalo wajib login. */
  userId: string;
  /** Cart subtotal saat ini. 0 untuk halaman member voucher tanpa cart context. */
  subtotal: number;
  /** Product di cart untuk scope-gate voucher brand/kategori/produk. undefined = skip gate (lihat buildVoucherListItems). */
  cartProducts?: EligibilityProductInput[];
  /** Override untuk testing. Default new Date(). */
  now?: Date;
};

/**
 * List voucher CUSTOMER yang relevan untuk user.
 *
 * Return semua voucher yang lolos `shouldHideVoucher` + eligibleUserIds
 * whitelist, sorted: applicable dulu (discount terbesar), lalu unavailable.
 *
 * Caller adapter:
 *  - Endpoint cart: filter ke `available` (applicable=true) + `unavailable`
 *  - Endpoint member: filter ke `eligible` (applicable=true) + `ineligible`
 *
 * Performance: 2 queries (vouchers + user used orders) + 1 user lookup +
 * 1 successful order count. Total ~30-50ms untuk voucher pool <100.
 */
export async function listUserVouchers(
  params: ListUserVouchersParams,
): Promise<ListUserVouchersResult> {
  const { userId, subtotal, cartProducts } = params;
  const now = params.now ?? new Date();

  // Fetch semua voucher CUSTOMER yg user-nya berhak (publik admin atau
  // owned by user). Filter detail (expired, usage limit, dll) dilakukan
  // setelah fetch — beberapa cek butuh cross-reference user orders.
  const [vouchers, userUsedOrders, user, successfulOrderCount] = await Promise.all([
    prisma.voucher.findMany({
      where: {
        sourceType: "CUSTOMER",
        // Voucher publik admin (userId=null) ATAU voucher owned by user.
        // Inilah perbaikan core bug — sebelumnya endpoint member filter
        // `userId: session.sub` doang → voucher publik admin tidak muncul.
        OR: [{ userId: null }, { userId }],
      },
      orderBy: { createdAt: "desc" },
    }),
    // Voucher code yg user sudah pernah pakai (di slot mana saja).
    // Dipakai untuk isVoucherUsageLimitReached check (per-user limit).
    prisma.order.findMany({
      where: {
        userId,
        OR: [
          { voucherCode: { not: null } },
          { freeShippingVoucherCode: { not: null } },
          { productVoucherCode: { not: null } },
          { shippingVoucherCode: { not: null } },
          { loyaltyVoucherCode: { not: null } },
          { manualVoucherCode: { not: null } },
          { privateVoucherCode: { not: null } },
        ],
      },
      select: {
        createdAt: true,
        voucherCode: true,
        freeShippingVoucherCode: true,
        productVoucherCode: true,
        shippingVoucherCode: true,
        loyaltyVoucherCode: true,
        manualVoucherCode: true,
        privateVoucherCode: true,
      },
    }),
    prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, createdAt: true },
    }),
    // Untuk NEW_MEMBER eligibility check (excludes CANCELLED/REFUNDED).
    prisma.order.count({
      where: {
        userId,
        status: { notIn: ["CANCELLED", "REFUNDED"] },
      },
    }),
  ]);

  const userCtx: VoucherUserContext = {
    isLoggedIn: true,
    userId,
    createdAt: user?.createdAt ?? null,
    successfulOrderCount,
  };

  const allBrandIds = vouchers.flatMap((v) => v.eligibleBrandIds);
  const brandNamesById = await loadBrandNamesByIds(allBrandIds);

  return {
    items: buildVoucherListItems({
      vouchers,
      userUsedOrders,
      userCtx,
      subtotal,
      now,
      cartProducts,
      brandNamesById,
    }),
  };
}

/**
 * Pure function untuk apply filter + transform — testable tanpa Prisma.
 *
 * Dipisah dari `listUserVouchers` supaya bisa di-test dengan voucher
 * fixture (vouchers + userOrders + userCtx) tanpa setup DB.
 *
 * Semua aturan visibility ada di sini — single source of truth.
 */
export function buildVoucherListItems(input: {
  vouchers: Voucher[];
  userUsedOrders: VoucherUsageOrder[];
  userCtx: VoucherUserContext;
  subtotal: number;
  now: Date;
  /** undefined = cart contents unknown, skip scope gate (backward-compat). Array (incl. []) = exact cart contents, gate scoped vouchers against it. */
  cartProducts?: EligibilityProductInput[];
  brandNamesById?: Map<string, string>;
}): VoucherListItem[] {
  const { vouchers, userUsedOrders, userCtx, subtotal, now, cartProducts, brandNamesById = new Map() } = input;
  const userId = userCtx.userId;
  const items: VoucherListItem[] = [];

  for (const v of vouchers) {
    // Permanent hide: expired, inactive, max usage, user sudah pakai.
    if (shouldHideVoucher(v, userUsedOrders, now)) continue;

    // Whitelist eligibleUserIds: kalau non-empty dan user TIDAK di list,
    // hide total (security — voucher VIP tidak boleh bocor). Match
    // pattern di app/api/cart/vouchers/validate-private/route.ts.
    if (
      v.eligibleUserIds.length > 0 &&
      (!userId || !v.eligibleUserIds.includes(userId))
    ) {
      continue;
    }

    const hasProductScope = voucherHasScope(v);

    // Bug fix: voucher scoped ke produk/kategori/brand tertentu HARUS
    // dicek terhadap isi cart yang sesungguhnya -- sebelumnya listing ini
    // cuma hitung dari subtotal, jadi voucher "Khusus Happy Dog" muncul
    // "available" walau keranjang tidak ada produk Happy Dog sama sekali,
    // baru gagal saat checkout/recalculate (yang sudah benar). cartProducts
    // undefined (caller belum kirim, mis. app lama) tetap permissive supaya
    // tidak regress voucher yang sebelumnya applicable.
    const scopeUnmatched =
      cartProducts !== undefined && !cartMatchesVoucherScope(v, cartProducts);

    // Nama brand voucher (null kalau tidak scoped ke brand / brand tidak
    // ke-resolve di brandNamesById). Dipakai untuk display DAN untuk alasan
    // disabled yang spesifik brand.
    const brandName = formatVoucherBrandName(v.eligibleBrandIds, brandNamesById);

    // Transient disabled state: belum mulai / NEW_MEMBER mismatch /
    // subtotal kurang / scope tidak cocok dengan isi cart. Voucher tetap
    // tampil dengan reason. Kalau mismatch-nya karena brand, sebut nama
    // brand supaya user paham harus tambah produk brand itu.
    const disabledReason =
      getVoucherDisabledReason(v, subtotal, userCtx, now) ??
      (scopeUnmatched
        ? brandName
          ? `Belum ada produk brand ${brandName} di keranjang`
          : "Voucher tidak berlaku untuk produk di keranjang"
        : null);
    const discount = disabledReason ? 0 : calcVoucherDiscount(subtotal, v);
    const isFreeShipping = isFreeShippingVoucher(v);
    // Free shipping voucher: applicable bahkan kalau discount=0 (karena
    // discount-nya di shipping fee, dihitung di checkout/recalculate
    // bukan di sini — listing tidak tau shipping fee).
    const applicable =
      disabledReason === null && (discount > 0 || isFreeShipping);

    items.push({
      id: v.id,
      name: v.name,
      code: v.code,
      description: v.description,
      discountPercent: v.discountPercent,
      discountAmount: v.discountAmount,
      maxDiscountAmount: v.maxDiscountAmount,
      minimumOrder: v.minimumOrder,
      expiresAt: v.expiresAt,
      sourceType: v.sourceType,
      type: voucherTypeOf(v),
      visibility: voucherVisibilityOf(v),
      discountScope: voucherScopeOf(v),
      discount,
      applicable,
      disabledReason:
        disabledReason ??
        (!isFreeShipping && discount === 0 && subtotal > 0
          ? "Voucher tidak memberikan potongan untuk pesanan ini"
          : null),
      hasProductScope,
      brandName,
    });
  }

  // Sort: applicable dulu (best discount duluan), lalu disabled.
  items.sort((a, b) => {
    if (a.applicable !== b.applicable) return a.applicable ? -1 : 1;
    return b.discount - a.discount;
  });

  return items;
}
