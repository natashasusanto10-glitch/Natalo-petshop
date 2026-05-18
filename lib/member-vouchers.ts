import type { Voucher } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { getNewMemberVoucherDisabledReason, shouldHideVoucher } from "@/lib/voucher-helpers";

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
        createdAt: true,
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

  const userCtx = {
    isLoggedIn: true,
    userId,
    createdAt: user?.createdAt ?? null,
    successfulOrderCount,
  };

  return vouchers.filter(
    (voucher) =>
      !shouldHideVoucher(voucher, usedOrders, now) &&
      !getNewMemberVoucherDisabledReason(voucher, userCtx, now),
  );
}
