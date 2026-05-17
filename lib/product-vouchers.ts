import { prisma } from "@/lib/prisma";

export type ProductVoucherItem = {
  id: string;
  title: string;
  description: string | null;
  label: string;
  type: "member";
  discountPercent: number | null;
  discountAmount: number | null;
  minimumOrder: number;
  kind: "PRODUCT_DISCOUNT" | "FREE_SHIPPING" | "LOYALTY_CLAIM" | "MANUAL_PRIVATE";
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
  kind?: string | null;
}) {
  if (voucher.kind === "FREE_SHIPPING") return "Gratis Ongkir";
  if (voucher.discountPercent && voucher.discountPercent > 0) {
    return `Diskon ${voucher.discountPercent}%`;
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

  const [rows, usedOrders] = await Promise.all([
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
        minimumOrder: true,
        maxUsage: true,
        usedCount: true,
        expiresAt: true,
        kind: true,
      },
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

  return rows
    .filter((voucher) => {
      if (usedCodes.has(voucher.code)) return false;
      if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) {
        return false;
      }
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
      minimumOrder: voucher.minimumOrder,
      kind: voucher.kind,
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
