import type { Voucher } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { getNewMemberVoucherDisabledReason, shouldHideVoucher } from "@/lib/voucher-helpers";
import { collectOrderVoucherCodes } from "@/lib/voucher-kind";

export type ActiveMemberVoucher = Voucher;

export async function loadActiveMemberVouchers(
  userId: string,
  now = new Date(),
): Promise<ActiveMemberVoucher[]> {
  const [vouchers, usedOrders, user, successfulOrderCount] = await Promise.all([
    prisma.voucher.findMany({
      where: {
        userId,
        sourceType: "CUSTOMER",
        isActive: true,
        startsAt: { lte: now },
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
      orderBy: { createdAt: "desc" },
    }),
    prisma.order.findMany({
      where: {
        userId,
        OR: [
          { voucherCode: { not: null } },
          { productVoucherCode: { not: null } },
          { shippingVoucherCode: { not: null } },
          { loyaltyVoucherCode: { not: null } },
          { manualVoucherCode: { not: null } },
        ],
      },
      select: {
        voucherCode: true,
        productVoucherCode: true,
        shippingVoucherCode: true,
        loyaltyVoucherCode: true,
        manualVoucherCode: true,
      },
    }),
    prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, createdAt: true },
    }),
    prisma.order.count({
      where: {
        userId,
        status: { notIn: ["CANCELLED", "REFUNDED"] },
      },
    }),
  ]);

  const usedCodes = new Map<string, number>();
  for (const order of usedOrders) {
    for (const code of collectOrderVoucherCodes(order)) {
      usedCodes.set(code, (usedCodes.get(code) ?? 0) + 1);
    }
  }

  const userCtx = {
    isLoggedIn: true,
    userId,
    createdAt: user?.createdAt ?? null,
    successfulOrderCount,
  };

  return vouchers.filter(
    (voucher) =>
      !shouldHideVoucher(voucher, usedCodes, now) &&
      !getNewMemberVoucherDisabledReason(voucher, userCtx, now),
  );
}
