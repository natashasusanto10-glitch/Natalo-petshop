import { prisma } from "@/lib/prisma";
import {
  getNewMemberVoucherDisabledReason,
  isVoucherUsageLimitReached,
  type VoucherUsageLimitPeriodValue,
} from "@/lib/voucher-helpers";

export type ProductVoucherPreview = {
  id: string;
  title: string;
  description: string | null;
  badgeLabel: string;
  sheetTitle: string;
  sheetSubtitle: string;
  discountPercent: number | null;
  discountAmount: number | null;
  maxDiscountAmount: number | null;
  minimumOrder: number;
  savingAmount: number | null;
  expiresAt: string | null;
  type: "PUBLIC_PRODUCT_DISCOUNT";
  discountScope: "PRODUCT";
  targetUser: "ALL_MEMBERS" | "NEW_MEMBER";
  loginRequired: true;
};

type ProductVoucherProductInput = {
  id: string;
  price: number;
  categoryId?: string | null;
  categorySlug?: string | null;
};

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
  kind:
    | "PRODUCT_DISCOUNT"
    | "FREE_SHIPPING"
    | "LOYALTY_CLAIM"
    | "MANUAL_PRIVATE";
  targetUser: "ALL_MEMBERS" | "NEW_MEMBER";
  usageLimitPeriod: VoucherUsageLimitPeriodValue;
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
  options: { take?: number } = {}
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
        usageLimitPeriod: true,
        usageLimitPerUser: true,
      },
    }),
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

  return rows
    .filter((voucher) => {
      if (isVoucherUsageLimitReached(voucher, usedOrders, now)) return false;
      if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) {
        return false;
      }
      if (getNewMemberVoucherDisabledReason(voucher, userCtx, now))
        return false;
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
      usageLimitPeriod: voucher.usageLimitPeriod,
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

type PublicProductVoucherRow = {
  id: string;
  name: string | null;
  code: string;
  description: string | null;
  discountPercent: number | null;
  discountAmount: number | null;
  maxDiscountAmount: number | null;
  minimumOrder: number;
  maxUsage: number | null;
  usedCount: number;
  expiresAt: Date | null;
  targetUser: "ALL_MEMBERS" | "NEW_MEMBER";
  eligibleUserIds: string[];
  eligibleProductIds: string[];
  eligibleCategoryIds: string[];
};

function voucherAppliesToProduct(
  voucher: Pick<
    PublicProductVoucherRow,
    "eligibleProductIds" | "eligibleCategoryIds"
  >,
  product: ProductVoucherProductInput
) {
  const productIds = new Set(voucher.eligibleProductIds ?? []);
  const categoryIds = new Set(voucher.eligibleCategoryIds ?? []);

  if (productIds.size === 0 && categoryIds.size === 0) return true;
  if (productIds.has(product.id)) return true;
  if (product.categoryId && categoryIds.has(product.categoryId)) return true;
  // Safety untuk data lama/admin input manual yang mungkin memakai slug.
  if (product.categorySlug && categoryIds.has(product.categorySlug))
    return true;
  return false;
}

function previewSavingAmount(
  voucher: Pick<
    PublicProductVoucherRow,
    "discountPercent" | "discountAmount" | "maxDiscountAmount" | "minimumOrder"
  >,
  product: ProductVoucherProductInput
) {
  const base = Math.max(0, voucher.minimumOrder || product.price || 0);
  let saving = 0;
  if (voucher.discountPercent && voucher.discountPercent > 0) {
    saving += Math.floor((base * voucher.discountPercent) / 100);
  }
  if (voucher.discountAmount && voucher.discountAmount > 0) {
    saving += voucher.discountAmount;
  }
  if (voucher.maxDiscountAmount && voucher.maxDiscountAmount > 0) {
    saving = Math.min(saving, voucher.maxDiscountAmount);
  }
  return saving > 0 ? saving : null;
}

function voucherPreviewLabel(
  voucher: PublicProductVoucherRow,
  savingAmount: number | null
) {
  if (savingAmount && savingAmount > 0) {
    const cappedOrMinimum =
      (voucher.maxDiscountAmount ?? 0) > 0 || voucher.minimumOrder > 0;
    return `Hemat ${cappedOrMinimum ? "s.d. " : ""}${formatRupiahShort(
      savingAmount
    )}`;
  }
  if (voucher.discountPercent && voucher.discountPercent > 0) {
    return `Hemat ${voucher.discountPercent}%`;
  }
  if (voucher.discountAmount && voucher.discountAmount > 0) {
    return `Hemat ${formatRupiahShort(voucher.discountAmount)}`;
  }
  return "Voucher produk Natalo";
}

function buildProductVoucherPreview(
  voucher: PublicProductVoucherRow,
  product: ProductVoucherProductInput
): ProductVoucherPreview | null {
  const savingAmount = previewSavingAmount(voucher, product);
  const badgeLabel = voucherPreviewLabel(voucher, savingAmount);
  if (!badgeLabel) return null;

  return {
    id: voucher.id,
    title: voucher.name ?? voucherTitle(voucher),
    description: voucher.description,
    badgeLabel,
    sheetTitle: voucherTitle(voucher),
    sheetSubtitle:
      voucher.minimumOrder > 0
        ? `Min. belanja ${formatRupiahShort(voucher.minimumOrder)}`
        : "Tanpa minimum belanja",
    discountPercent: voucher.discountPercent,
    discountAmount: voucher.discountAmount,
    maxDiscountAmount: voucher.maxDiscountAmount,
    minimumOrder: voucher.minimumOrder,
    savingAmount,
    expiresAt: voucher.expiresAt ? voucher.expiresAt.toISOString() : null,
    type: "PUBLIC_PRODUCT_DISCOUNT",
    discountScope: "PRODUCT",
    targetUser: voucher.targetUser,
    loginRequired: true,
  };
}

async function loadPublicProductDiscountVouchers() {
  const now = new Date();
  const vouchers = await prisma.voucher.findMany({
    where: {
      isActive: true,
      sourceType: "CUSTOMER",
      type: "PUBLIC_PRODUCT_DISCOUNT",
      visibility: "PUBLIC",
      discountScope: "PRODUCT",
      userId: null,
      startsAt: { lte: now },
      OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
    },
    orderBy: [
      { expiresAt: "asc" },
      { discountAmount: "desc" },
      { discountPercent: "desc" },
      { createdAt: "desc" },
    ],
    select: {
      id: true,
      name: true,
      code: true,
      description: true,
      discountPercent: true,
      discountAmount: true,
      maxDiscountAmount: true,
      minimumOrder: true,
      maxUsage: true,
      usedCount: true,
      expiresAt: true,
      targetUser: true,
      eligibleUserIds: true,
      eligibleProductIds: true,
      eligibleCategoryIds: true,
    },
    take: 40,
  });

  return vouchers.filter((voucher) => {
    if (voucher.eligibleUserIds.length > 0) return false;
    if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) {
      return false;
    }
    return true;
  });
}

export async function attachPublicProductVoucherPreviews<
  T extends ProductVoucherProductInput
>(
  products: T[]
): Promise<Array<T & { voucherPreview: ProductVoucherPreview | null }>> {
  if (products.length === 0) return [];
  try {
    const vouchers = await loadPublicProductDiscountVouchers();
    if (vouchers.length === 0) {
      return products.map((product) => ({ ...product, voucherPreview: null }));
    }

    return products.map((product) => {
      const previews = vouchers
        .filter((voucher) => voucherAppliesToProduct(voucher, product))
        .map((voucher) => buildProductVoucherPreview(voucher, product))
        .filter((preview): preview is ProductVoucherPreview => Boolean(preview))
        .sort((a, b) => {
          const amountDelta = (b.savingAmount ?? 0) - (a.savingAmount ?? 0);
          if (amountDelta !== 0) return amountDelta;
          return (b.discountPercent ?? 0) - (a.discountPercent ?? 0);
        });

      return {
        ...product,
        voucherPreview: previews[0] ?? null,
      };
    });
  } catch {
    return products.map((product) => ({ ...product, voucherPreview: null }));
  }
}

export async function loadPublicProductVoucherPreview(
  product: ProductVoucherProductInput
) {
  const [withPreview] = await attachPublicProductVoucherPreviews([product]);
  return withPreview?.voucherPreview ?? null;
}
