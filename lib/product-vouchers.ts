import { prisma } from "@/lib/prisma";
import { collectOrderVoucherCodes } from "@/lib/voucher-kind";
import { getNewMemberVoucherDisabledReason } from "@/lib/voucher-helpers";

export type ProductVoucherItem = {
  id: string;
  title: string;
  description: string | null;
  label: string;
  type: "member";
  discountPercent: number | null;
  discountAmount: number | null;
  maxDiscountAmount: number | null;
  minimumOrder: number;
  kind: "PRODUCT_DISCOUNT" | "FREE_SHIPPING" | "LOYALTY_CLAIM" | "MANUAL_PRIVATE";
  targetUser: "ALL_MEMBERS" | "NEW_MEMBER";
  minPurchase: number;
  expiresAt: string | null;
  visibility: "member";
  isPrivate: false;
  isManualOnly: false;
  usedByCurrentUser: false;
  isActive: true;
  isExpired: false;
};

function formatRupiahShort(n: number) {
  return `Rp${new Intl.NumberFormat("id-ID").format(n)}`;
}

function voucherTitle(voucher: {
  discountPercent: number | null;
  discountAmount: number | null;
  maxDiscountAmount?: number | null;
  kind?: string | null;
}) {
  if (voucher.kind === "FREE_SHIPPING") return "Gratis Ongkir";
  if (voucher.discountPercent && voucher.discountPercent > 0) {
    const cap =
      voucher.maxDiscountAmount && voucher.maxDiscountAmount > 0
        ? ` hingga ${formatRupiahShort(voucher.maxDiscountAmount)}`
        : "";
    return `Diskon ${voucher.discountPercent}%${cap}`;
  }
  if (voucher.discountAmount && voucher.discountAmount > 0) {
    return `Diskon ${formatRupiahShort(voucher.discountAmount)}`;
  }
  return "Voucher Member Natalo";
}

export async function loadVisibleProductVouchers(
  userId: string | null,
  options: { take?: number } = {},
): Promise<ProductVoucherItem[]> {
  if (!userId) return [];

  const now = new Date();
  const take = options.take ?? 6;

  const [rows, usedOrders, user, successfulOrderCount] = await Promise.all([
    prisma.voucher.findMany({
      where: {
        isActive: true,
        sourceType: "CUSTOMER",
        startsAt: { lte: now },
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
        AND: [{ OR: [{ userId: null }, { userId }] }],
      },
      orderBy: [{ expiresAt: "asc" }, { createdAt: "desc" }],
      take: take * 2,
      select: {
        id: true,
        code: true,
        description: true,
        discountPercent: true,
        discountAmount: true,
        maxDiscountAmount: true,
        minimumOrder: true,
        maxUsage: true,
        usedCount: true,
        expiresAt: true,
        kind: true,
        targetUser: true,
        newMemberMaxAccountAgeDays: true,
        newMemberRequireNoSuccessfulOrder: true,
        usageLimitPerUser: true,
      },
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

  return rows
    .filter((voucher) => {
      const usageLimit = voucher.usageLimitPerUser ?? 1;
      if (usageLimit > 0 && (usedCodes.get(voucher.code) ?? 0) >= usageLimit) return false;
      if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) {
        return false;
      }
      if (getNewMemberVoucherDisabledReason(voucher, userCtx, now)) return false;
      return true;
    })
    .slice(0, take)
    .map((voucher) => ({
      id: voucher.id,
      title: voucherTitle(voucher),
      description:
        voucher.minimumOrder > 0
          ? `Min. belanja ${formatRupiahShort(voucher.minimumOrder)}`
          : "Tanpa minimum belanja",
      label: "Eksklusif Member Natalo",
      type: "member",
      discountPercent: voucher.discountPercent,
      discountAmount: voucher.discountAmount,
      maxDiscountAmount: voucher.maxDiscountAmount,
      minimumOrder: voucher.minimumOrder,
      kind: voucher.kind,
      targetUser: voucher.targetUser,
      minPurchase: voucher.minimumOrder,
      expiresAt: voucher.expiresAt ? voucher.expiresAt.toISOString() : null,
      visibility: "member",
      isPrivate: false,
      isManualOnly: false,
      usedByCurrentUser: false,
      isActive: true,
      isExpired: false,
    }));
}
