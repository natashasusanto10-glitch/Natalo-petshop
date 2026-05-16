import type { Voucher } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { shouldHideVoucher } from "@/lib/voucher-helpers";

export type ActiveMemberVoucher = Voucher;

export async function loadActiveMemberVouchers(
  userId: string,
  now = new Date(),
): Promise<ActiveMemberVoucher[]> {
  const [vouchers, usedOrders] = await Promise.all([
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
        OR: [{ voucherCode: { not: null } }, { manualVoucherCode: { not: null } }],
      },
      select: { voucherCode: true, manualVoucherCode: true },
    }),
  ]);

  const usedCodes = new Set<string>();
  for (const order of usedOrders) {
    if (order.voucherCode) usedCodes.add(order.voucherCode);
    if (order.manualVoucherCode) usedCodes.add(order.manualVoucherCode);
  }

  return vouchers.filter((voucher) => !shouldHideVoucher(voucher, usedCodes, now));
}
