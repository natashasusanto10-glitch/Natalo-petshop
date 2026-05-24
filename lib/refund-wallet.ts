/**
 * Refund Wallet helpers — atomic balance mutations + scope-aware
 * voucher allocation calculation untuk refund.
 *
 * Aturan Natalo (lihat spec):
 *  - Refund = nilai BERSIH yang user bayar untuk item (harga - alokasi
 *    voucher proporsional - alokasi saldo refund proporsional).
 *  - Voucher allocation scope-aware:
 *      - PRODUCT discount voucher (umum) → alokasi proporsional ke
 *        semua item.
 *      - PRODUCT discount voucher (scoped via eligibleProductIds /
 *        eligibleCategoryIds) → alokasi proporsional cuma ke item
 *        yang masuk scope.
 *      - SHIPPING voucher (FREE_SHIPPING) → TIDAK alokasi ke produk
 *        (refund produk full harga - voucher product allocation saja).
 *  - Saldo refund yang dipakai → balik ke saldo (REVERSAL), bukan ke
 *    metode bayar.
 *
 * Atomic guarantee: semua credit/debit/reversal HARUS via helper di
 * sini. Direct mutate `RefundWallet.availableBalance` di endpoint =
 * forbidden (no audit trail di ledger).
 */

import type { Prisma, PrismaClient } from "@prisma/client";
import { prisma } from "@/lib/prisma";

// ─── Type definitions untuk calculation input ────────────────────────

export type RefundOrderItemInput = {
  id: string;
  productId: string;
  /** Per-unit price snapshot saat checkout. */
  price: number;
  quantity: number;
  /** categoryId dari product master (untuk scope check). */
  categoryId: string | null;
};

export type RefundVoucherInput = {
  code: string;
  /** Nominal diskon AKTUAL yang ke-apply (sudah after cap). */
  actualDiscountAmount: number;
  /**
   * Scope rule. Kalau scope=SHIPPING, voucher tidak alokasi ke produk
   * sama sekali (refund item full harga, voucher gratis ongkir tidak
   * affect). Kalau scope=PRODUCT, alokasi proporsional sesuai
   * eligibleProductIds/CategoryIds (kalau ada) atau semua item (kalau
   * tidak ada scope filter).
   */
  scope: "PRODUCT" | "SHIPPING";
  eligibleProductIds: string[];
  eligibleCategoryIds: string[];
};

export type RefundCalculationInput = {
  items: RefundOrderItemInput[];
  vouchers: RefundVoucherInput[];
  /** Saldo refund yang dipakai user di order ini (kalau ada). */
  refundBalanceUsed: number;
  /** Item yang mau di-refund (item kosong / batal). */
  targetItemId: string;
};

export type RefundCalculationResult = {
  /** Total refund amount untuk item ini (= harga - alokasi). */
  refundAmount: number;
  /** Breakdown per voucher: { "DISKON15": 6000, "POIN50K": 20000 }. */
  voucherAllocations: Record<string, number>;
  /** Saldo refund yang dipakai untuk item ini (jadi reversal). */
  saldoAllocationForItem: number;
  /** Nilai bersih dibayar user (item price - all allocations). */
  netPaidAmount: number;
  /** Item price gross (price × quantity). */
  itemGrossPrice: number;
};

/**
 * Hitung refund amount untuk SATU item dengan scope-aware voucher
 * allocation. Pattern sama dengan `eligibleProductSubtotal` di
 * `app/api/checkout/recalculate/route.ts` — refactored untuk reuse
 * di refund flow.
 *
 * Logic:
 *  1. Untuk setiap voucher, hitung `eligibleSubtotalForVoucher` =
 *     subtotal item yang masuk scope voucher.
 *  2. Kalau target item TIDAK masuk scope voucher itu → allocation = 0.
 *  3. Kalau masuk scope → allocation = (itemPrice / eligibleSubtotal)
 *     × voucher.actualDiscountAmount.
 *  4. Sum semua voucher allocations + saldo allocation = total deduction.
 *  5. Refund = itemPrice - (voucher deductions) — saldo BUKAN dikurangi
 *     dari refund (saldo balik ke saldo sebagai reversal terpisah).
 *
 * Edge cases handled:
 *  - SHIPPING voucher → skip allocation ke produk (free shipping
 *    tidak affect harga produk).
 *  - Voucher tanpa eligibleProductIds + eligibleCategoryIds = scope
 *    ke semua item (default umum).
 *  - Item dengan categoryId null tapi voucher require category match
 *    → tidak masuk scope.
 *  - Division by zero saat eligibleSubtotal = 0 → allocation = 0.
 */
export function calculateRefundForItem(
  input: RefundCalculationInput,
): RefundCalculationResult {
  const targetItem = input.items.find((it) => it.id === input.targetItemId);
  if (!targetItem) {
    throw new Error(`Item ${input.targetItemId} tidak ditemukan di order`);
  }

  const itemGrossPrice = targetItem.price * targetItem.quantity;
  const orderSubtotal = input.items.reduce(
    (sum, it) => sum + it.price * it.quantity,
    0,
  );

  const voucherAllocations: Record<string, number> = {};
  let totalVoucherDeduction = 0;

  for (const voucher of input.vouchers) {
    // Shipping voucher tidak alokasi ke produk.
    if (voucher.scope === "SHIPPING") {
      voucherAllocations[voucher.code] = 0;
      continue;
    }

    // Determine scope: kalau ada eligibleProductIds atau
    // eligibleCategoryIds, voucher cuma berlaku untuk item yang
    // match. Kalau kosong, voucher berlaku untuk semua item.
    const hasProductScope = voucher.eligibleProductIds.length > 0;
    const hasCategoryScope = voucher.eligibleCategoryIds.length > 0;
    const hasAnyScope = hasProductScope || hasCategoryScope;

    const isItemInScope = (item: RefundOrderItemInput): boolean => {
      if (!hasAnyScope) return true;
      if (hasProductScope && voucher.eligibleProductIds.includes(item.productId)) {
        return true;
      }
      if (
        hasCategoryScope &&
        item.categoryId &&
        voucher.eligibleCategoryIds.includes(item.categoryId)
      ) {
        return true;
      }
      return false;
    };

    // Check target item dalam scope.
    if (!isItemInScope(targetItem)) {
      voucherAllocations[voucher.code] = 0;
      continue;
    }

    // Hitung eligibleSubtotal = sum item yang masuk scope voucher ini.
    const eligibleSubtotal = input.items
      .filter(isItemInScope)
      .reduce((sum, it) => sum + it.price * it.quantity, 0);

    if (eligibleSubtotal <= 0) {
      voucherAllocations[voucher.code] = 0;
      continue;
    }

    // Proportional allocation.
    const allocation = Math.round(
      (itemGrossPrice / eligibleSubtotal) * voucher.actualDiscountAmount,
    );

    voucherAllocations[voucher.code] = allocation;
    totalVoucherDeduction += allocation;
  }

  // Saldo allocation proporsional ke total subtotal (tidak scope-aware
  // karena saldo adalah cash equivalent, berlaku universal).
  const saldoAllocationForItem =
    input.refundBalanceUsed > 0 && orderSubtotal > 0
      ? Math.round((itemGrossPrice / orderSubtotal) * input.refundBalanceUsed)
      : 0;

  // Nilai bersih = harga - voucher - saldo (yang user benar-benar bayar
  // via metode bayar). Saldo bukan dikurangi dari refund (akan ada
  // reversal terpisah).
  const netPaidAmount = Math.max(
    0,
    itemGrossPrice - totalVoucherDeduction - saldoAllocationForItem,
  );

  // Refund amount = item gross - voucher allocations.
  // Saldo allocation jadi reversal terpisah (balik ke saldo, bukan ke
  // refund balance baru). Untuk MVP single destination, refund total
  // ke saldo = netPaidAmount + saldoAllocationForItem.
  //
  // Pattern: REFUND_BALANCE destination → user dapat semua di saldo,
  // tidak peduli sumber asli (saldo atau metode bayar).
  const refundAmount = netPaidAmount + saldoAllocationForItem;

  return {
    refundAmount,
    voucherAllocations,
    saldoAllocationForItem,
    netPaidAmount,
    itemGrossPrice,
  };
}

// ─── Atomic Wallet Operations ────────────────────────────────────────

type TransactionClient = Omit<
  PrismaClient,
  "$connect" | "$disconnect" | "$on" | "$transaction" | "$use" | "$extends"
> & {
  refundWallet: Prisma.RefundWalletDelegate;
  refundWalletLedger: Prisma.RefundWalletLedgerDelegate;
};

/**
 * Get atau lazy-create RefundWallet untuk user. Aman di-call berkali2 —
 * idempotent via unique constraint userId.
 *
 * Dipakai sebelum credit/debit operation. Wallet dibuat saat pertama
 * kali user terima refund atau pakai saldo.
 */
export async function getOrCreateWallet(
  userId: string,
  tx?: TransactionClient,
) {
  const client = tx ?? prisma;
  const existing = await client.refundWallet.findUnique({
    where: { userId },
  });
  if (existing) return existing;
  return client.refundWallet.create({
    data: { userId },
  });
}

/**
 * Credit saldo refund (admin issue refund). Atomic — wrap di transaction
 * + create ledger entry.
 *
 * @throws Error kalau wallet FROZEN atau amount <= 0.
 */
export async function creditWallet(input: {
  userId: string;
  amount: number;
  sourceOrderId?: string | null;
  sourceRefundCaseId?: string | null;
  note?: string | null;
  createdByAdminId?: string | null;
  type?: "CREDIT" | "REVERSAL" | "ADJUSTMENT";
}): Promise<{
  newBalance: number;
  ledgerEntryId: string;
}> {
  if (input.amount <= 0) {
    throw new Error("Credit amount must be positive");
  }
  return prisma.$transaction(async (tx) => {
    const wallet = await getOrCreateWallet(input.userId, tx);
    if (wallet.status === "FROZEN") {
      throw new Error("Wallet is frozen, cannot credit");
    }
    const balanceBefore = wallet.availableBalance;
    const balanceAfter = balanceBefore + input.amount;
    await tx.refundWallet.update({
      where: { id: wallet.id },
      data: { availableBalance: balanceAfter },
    });
    const ledger = await tx.refundWalletLedger.create({
      data: {
        walletId: wallet.id,
        userId: input.userId,
        type: input.type ?? "CREDIT",
        amount: input.amount,
        balanceBefore,
        balanceAfter,
        sourceOrderId: input.sourceOrderId ?? null,
        sourceRefundCaseId: input.sourceRefundCaseId ?? null,
        note: input.note ?? null,
        createdByAdminId: input.createdByAdminId ?? null,
      },
    });
    return { newBalance: balanceAfter, ledgerEntryId: ledger.id };
  });
}

/**
 * Debit saldo refund (user pakai saldo di checkout). Atomic + ledger.
 *
 * @throws Error kalau wallet FROZEN, insufficient balance, atau amount <= 0.
 */
export async function debitWallet(input: {
  userId: string;
  amount: number;
  sourceOrderId: string;
  note?: string | null;
}): Promise<{
  newBalance: number;
  ledgerEntryId: string;
}> {
  if (input.amount <= 0) {
    throw new Error("Debit amount must be positive");
  }
  return prisma.$transaction(async (tx) => {
    const wallet = await getOrCreateWallet(input.userId, tx);
    if (wallet.status === "FROZEN") {
      throw new Error("Wallet is frozen, cannot debit");
    }
    if (wallet.availableBalance < input.amount) {
      throw new Error(
        `Insufficient balance: have ${wallet.availableBalance}, need ${input.amount}`,
      );
    }
    const balanceBefore = wallet.availableBalance;
    const balanceAfter = balanceBefore - input.amount;
    await tx.refundWallet.update({
      where: { id: wallet.id },
      data: { availableBalance: balanceAfter },
    });
    const ledger = await tx.refundWalletLedger.create({
      data: {
        walletId: wallet.id,
        userId: input.userId,
        type: "DEBIT",
        amount: input.amount,
        balanceBefore,
        balanceAfter,
        sourceOrderId: input.sourceOrderId,
        note: input.note ?? null,
      },
    });
    return { newBalance: balanceAfter, ledgerEntryId: ledger.id };
  });
}
