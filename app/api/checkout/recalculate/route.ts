import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { cartItemSchema } from "@/lib/validation";
import { buildCheckoutItemsFromInventory } from "@/lib/checkout-items";
import {
  calcVoucherScopedDiscount,
  voucherScopeOf,
  voucherTypeOf,
  voucherVisibilityOf,
  type VoucherTypeCode,
} from "@/lib/voucher-helpers";

/**
 * Aturan voucher checkout (lihat CLAUDE.md - Voucher business rules):
 * - Maks 4 voucher per checkout
 * - Maks 3 voucher CUSTOMER (diskon produk + gratis ongkir + loyalty)
 *   + 1 voucher SELLER_MANUAL/manual-private
 * - Voucher SELLER_MANUAL TIDAK muncul di daftar publik (filtered)
 * - SELLER_MANUAL hanya bisa via input kode manual
 * - Semua validasi & total dihitung di backend (source of truth)
 */

const recalculateSchema = z.object({
  items: z.array(cartItemSchema).default([]),
  shipping_fee: z.number().int().nonnegative().optional(),
  shippingCost: z.number().int().nonnegative().optional(),
  // Legacy single-code fields (backwards compat dgn klien lama)
  voucherCode: z.string().trim().optional().nullable(),
  customerVoucherCode: z.string().trim().optional().nullable(),
  // Four-slot voucher fields.
  productVoucherCode: z.string().trim().optional().nullable(),
  shippingVoucherCode: z.string().trim().optional().nullable(),
  loyaltyVoucherCode: z.string().trim().optional().nullable(),
  manualVoucherCode: z.string().trim().optional().nullable(),
  freeShippingVoucherCode: z.string().trim().optional().nullable(),
  productVoucherCode: z.string().trim().optional().nullable(),
  loyaltyVoucherCode: z.string().trim().optional().nullable(),
  privateVoucherCode: z.string().trim().optional().nullable(),
  autoApply: z.boolean().default(true),
  address: z
    .object({
      areaId: z.string().optional().nullable(),
      postalCode: z.string().optional().nullable(),
      latitude: z.number().nullable().optional(),
      longitude: z.number().nullable().optional(),
      city: z.string().optional().nullable(),
    })
    .optional(),
  shippingMethod: z
    .object({
      courierCode: z.string().optional().nullable(),
      courierService: z.string().optional().nullable(),
    })
    .optional(),
  paymentProvider: z.enum(["MANUAL", "MIDTRANS"]).optional().nullable(),
});

type VoucherSourceType = "CUSTOMER" | "SELLER_MANUAL";
type VoucherKind = "PRODUCT_DISCOUNT" | "FREE_SHIPPING" | "LOYALTY_CLAIM" | "MANUAL_PRIVATE";

type VoucherRow = {
  code: string;
  id: string;
  name: string | null;
  description: string | null;
  discountPercent: number | null;
  discountAmount: number | null;
  maxDiscountAmount: number | null;
  minimumOrder: number;
  startsAt: Date;
  expiresAt: Date | null;
  maxUsage: number | null;
  usedCount: number;
  usageLimitPerUser: number;
  isActive: boolean;
  sourceType: VoucherSourceType;
  kind: VoucherKind;
  targetUser: "ALL_MEMBERS" | "NEW_MEMBER";
  newMemberMaxAccountAgeDays: number | null;
  newMemberRequireNoSuccessfulOrder: boolean;
  usageLimitPeriod: "NONE" | "LIFETIME" | "DAY" | "WEEK" | "MONTH";
  usageLimitPerUser: number;
  userId: string | null;
  type: VoucherTypeCode;
  visibility: "PUBLIC" | "PRIVATE" | "USER_OWNED";
  discountScope: "PRODUCT" | "SHIPPING";
  eligibleUserIds: string[];
  eligibleProductIds: string[];
  eligibleCategoryIds: string[];
};

function calcDiscount(
  subtotal: number,
  voucher: Pick<VoucherRow, "discountPercent" | "discountAmount" | "maxDiscountAmount">,
) {
  if (isFreeShippingVoucher(voucher)) return Math.max(0, shippingFee);
  let discount = 0;
  if (voucher.discountPercent) discount += Math.floor((subtotal * voucher.discountPercent) / 100);
  if (voucher.discountAmount) discount += voucher.discountAmount;
  if (voucher.maxDiscountAmount && voucher.maxDiscountAmount > 0) {
    discount = Math.min(discount, voucher.maxDiscountAmount);
  }
  return Math.min(discount, subtotal);
}

function describeDiscount(discount: number, kind?: VoucherKind) {
  if (kind === "FREE_SHIPPING") return "Gratis Ongkir";
  return `Hemat Rp${new Intl.NumberFormat("id-ID").format(discount)}`;
}

function normalizeVoucher(voucher: VoucherRow, discount: number) {
  return {
    id: voucher.id,
    code: voucher.code,
    name: voucher.name,
    title: voucher.name ?? voucher.description ?? voucher.code,
    discount,
    description: voucher.description ?? describeDiscount(discount),
    discountPercent: voucher.discountPercent,
    discountAmount: voucher.discountAmount,
    maxDiscountAmount: voucher.maxDiscountAmount,
    minimumOrder: voucher.minimumOrder,
    expiresAt: voucher.expiresAt,
    sourceType: voucher.sourceType,
    type: voucherTypeOf(voucher),
    visibility: voucherVisibilityOf(voucher),
    discountScope: voucherScopeOf(voucher),
    status: "available" as const,
  };
}

function normalizeUnavailable(
  voucher: VoucherRow,
  reason: string,
  shortfall = 0,
) {
  return {
    id: voucher.id,
    code: voucher.code,
    name: voucher.name,
    title: voucher.name ?? voucher.description ?? voucher.code,
    discountPercent: voucher.discountPercent,
    discountAmount: voucher.discountAmount,
    maxDiscountAmount: voucher.maxDiscountAmount,
    description: voucher.description ?? "",
    minimumOrder: voucher.minimumOrder,
    shortfall,
    expiresAt: voucher.expiresAt,
    reason,
    sourceType: voucher.sourceType,
    type: voucherTypeOf(voucher),
    visibility: voucherVisibilityOf(voucher),
    discountScope: voucherScopeOf(voucher),
    status: "unavailable" as const,
  };
}

function emptyVoucherPayload(shippingFee: number) {
  return {
    subtotal: 0,
    shipping_fee: shippingFee,
    discount: 0,
    total: shippingFee,
    auto_applied_voucher: null,
    applied_voucher: null,
    applied_customer_voucher: null,
    applied_product_voucher: null,
    applied_shipping_voucher: null,
    applied_loyalty_voucher: null,
    applied_manual_voucher: null,
    available_vouchers: [],
    unavailable_vouchers: [],
    voucher_invalidated: false,
    invalidated_message: null,
    customer_voucher_error: null,
    product_voucher_error: null,
    shipping_voucher_error: null,
    loyalty_voucher_error: null,
    manual_voucher_error: null,
  };
}

export async function POST(request: NextRequest) {
  const json = await request.json().catch(() => null);
  const parsed = recalculateSchema.safeParse(json);

  if (!parsed.success) {
    return NextResponse.json(
      { message: "Data checkout tidak valid.", errors: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const input = parsed.data;
  const shippingFee = input.shipping_fee ?? input.shippingCost ?? 0;

  // Normalize codes — legacy `voucherCode` tetap dianggap voucher diskon produk
  // supaya klien lama tidak break. Slot baru mendukung 4 voucher Natalo.
  const legacyCustomerRequested = (
    input.customerVoucherCode ?? input.voucherCode ?? ""
  )
    .trim()
    .toUpperCase();
  const legacyManualRequested = (input.manualVoucherCode ?? "")
    .trim()
    .toUpperCase();
  const freeShippingRequested = (input.freeShippingVoucherCode ?? "")
    .trim()
    .toUpperCase();
  const productRequested = (
    input.productVoucherCode ?? legacyCustomerRequested
  )
    .trim()
    .toUpperCase();
  const loyaltyRequested = (input.loyaltyVoucherCode ?? "")
    .trim()
    .toUpperCase();
  const privateRequested = (
    input.privateVoucherCode ?? legacyManualRequested
  )
    .trim()
    .toUpperCase();

  if (input.items.length === 0) {
    return NextResponse.json({
      subtotal: 0,
      shipping_fee: shippingFee,
      discount: 0,
      discountAmount: 0,
      productDiscount: 0,
      shippingDiscount: 0,
      shippingCost: shippingFee,
      originalShippingCost: shippingFee,
      total: shippingFee,
      // Legacy fields (backwards compat — selalu reflect customer voucher)
      auto_applied_voucher: null,
      applied_voucher: null,
      // New dual-slot fields
      applied_customer_voucher: null,
      applied_manual_voucher: null,
      applied_free_shipping_voucher: null,
      applied_product_voucher: null,
      applied_loyalty_voucher: null,
      applied_private_voucher: null,
      available_vouchers: [],
      unavailable_vouchers: [],
      voucher_invalidated: false,
      invalidated_message: null,
      customer_voucher_error: null,
      manual_voucher_error: null,
    });
  }

  const requestedMap = new Map<
    string,
    { productId: string; variantId?: string | null; variantLabel?: string | null; quantity: number }
  >();

  for (const item of input.items) {
    const key = `${item.productId}:${item.variantId ?? ""}`;
    const current = requestedMap.get(key);
    requestedMap.set(key, {
      productId: item.productId,
      variantId: item.variantId ?? null,
      variantLabel: item.variantLabel ?? null,
      quantity: (current?.quantity ?? 0) + item.quantity,
    });
  }

  const productIds = [...new Set([...requestedMap.values()].map((item) => item.productId))];
  const variantIds = [
    ...new Set([...requestedMap.values()].map((item) => item.variantId).filter(Boolean)),
  ] as string[];

  const [session, products, variants] = await Promise.all([
    getSession("CUSTOMER"),
    prisma.product.findMany({
      where: { id: { in: productIds } },
      select: {
        id: true,
        name: true,
        price: true,
        discountPrice: true,
        stock: true,
        weightGram: true,
        categoryId: true,
        isActive: true,
        hasVariants: true,
      },
    }),
    variantIds.length
      ? prisma.productVariant.findMany({
          where: { id: { in: variantIds }, deletedAt: null, isActive: true },
          select: { id: true, productId: true, price: true, stock: true, weightGram: true },
        })
      : Promise.resolve([]),
  ]);

  const { checkoutItems, stockErrors } = buildCheckoutItemsFromInventory({
    requestedItems: requestedMap.values(),
    products,
    variants,
  });

  if (stockErrors.length > 0) {
    return NextResponse.json({ message: stockErrors.join(" ") }, { status: 409 });
  }

  const subtotal = checkoutItems.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const now = new Date();
  const productById = new Map(products.map((product) => [product.id, product]));

  function eligibleProductSubtotal(voucher: VoucherRow) {
    const productIds = new Set(voucher.eligibleProductIds ?? []);
    const categoryIds = new Set(voucher.eligibleCategoryIds ?? []);
    if (productIds.size === 0 && categoryIds.size === 0) return subtotal;
    return checkoutItems.reduce((sum, item) => {
      const product = productById.get(item.productId);
      const productMatch = productIds.has(item.productId);
      const categoryMatch =
        !!product?.categoryId && categoryIds.has(product.categoryId);
      return productMatch || categoryMatch ? sum + item.price * item.quantity : sum;
    }, 0);
  }

  const userUsedCodeCounts = new Map<string, number>();
  const bumpUsed = (code?: string | null) => {
    if (!code) return;
    userUsedCodeCounts.set(code, (userUsedCodeCounts.get(code) ?? 0) + 1);
  };

  if (session) {
    const userOrders = await prisma.order.findMany({
      where: {
        userId: session.sub,
        OR: [
          { voucherCode: { not: null } },
          { manualVoucherCode: { not: null } },
          { freeShippingVoucherCode: { not: null } },
          { productVoucherCode: { not: null } },
          { loyaltyVoucherCode: { not: null } },
          { privateVoucherCode: { not: null } },
        ],
      },
      select: {
        voucherCode: true,
        manualVoucherCode: true,
        freeShippingVoucherCode: true,
        productVoucherCode: true,
        loyaltyVoucherCode: true,
        privateVoucherCode: true,
      },
    });
    for (const order of userOrders) {
      bumpUsed(order.voucherCode);
      bumpUsed(order.manualVoucherCode);
      bumpUsed(order.freeShippingVoucherCode);
      bumpUsed(order.productVoucherCode);
      bumpUsed(order.loyaltyVoucherCode);
      bumpUsed(order.privateVoucherCode);
    }
  }

  function userUsageCount(voucher: VoucherRow) {
    return userUsedCodeCounts.get(voucher.code) ?? 0;
  }

  function discountFor(voucher: VoucherRow) {
    return calcVoucherScopedDiscount({
      subtotal,
      shippingFee,
      eligibleProductSubtotal: eligibleProductSubtotal(voucher),
      voucher,
    });
  }

  function validateVoucher(voucher: VoucherRow | null, expected: VoucherTypeCode) {
    if (!session) {
      return { voucher: null, error: "Login dulu untuk menggunakan voucher." };
    }
    if (!voucher || !voucher.isActive) {
      return { voucher: null, error: "Kode voucher tidak valid atau tidak tersedia untuk akun ini." };
    }
    const type = voucherTypeOf(voucher);
    if (type !== expected) {
      return {
        voucher: null,
        error:
          expected === "PRIVATE_MANUAL_CODE"
            ? "Kode voucher khusus tidak valid untuk slot manual."
            : "Voucher tidak sesuai dengan slot yang dipilih.",
      };
    }
    if (voucher.expiresAt && voucher.expiresAt <= now) {
      return { voucher: null, error: "Voucher sudah berakhir." };
    }
    if (voucher.startsAt > now) {
      return { voucher: null, error: "Voucher belum berlaku." };
    }
    if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) {
      return { voucher: null, error: "Kuota voucher sudah habis." };
    }
    if (userUsageCount(voucher) >= Math.max(1, voucher.usageLimitPerUser)) {
      return { voucher: null, error: "Kode voucher sudah pernah digunakan." };
    }
    if (voucher.minimumOrder > subtotal) {
      const shortfall = voucher.minimumOrder - subtotal;
      return {
        voucher: null,
        error: `Belanja kurang Rp${new Intl.NumberFormat("id-ID").format(shortfall)} lagi`,
      };
    }
    if (voucher.userId && voucher.userId !== session.sub) {
      return { voucher: null, error: "Voucher ini tidak tersedia untuk akun kamu." };
    }
    if (
      voucher.visibility === "PRIVATE" &&
      voucher.eligibleUserIds.length > 0 &&
      !voucher.eligibleUserIds.includes(session.sub)
    ) {
      return { voucher: null, error: "Kode voucher ini tidak tersedia untuk akun kamu." };
    }
    if (voucherScopeOf(voucher) === "PRODUCT" && eligibleProductSubtotal(voucher) <= 0) {
      return { voucher: null, error: "Voucher tidak berlaku untuk produk ini." };
    }
    const discount = discountFor(voucher);
    if (discount <= 0) {
      return {
        voucher: null,
        error: "Voucher tidak memberikan potongan untuk pesanan ini.",
      };
    }
    return { voucher: normalizeVoucher(voucher, discount), error: null };
  }

  const visibleVouchers = session
    ? ((await prisma.voucher.findMany({
        where: {
          sourceType: "CUSTOMER",
          OR: [
            { visibility: "PUBLIC", userId: null },
            { visibility: "USER_OWNED", userId: session.sub },
            { userId: session.sub },
          ],
        },
        orderBy: { createdAt: "desc" },
      })) as VoucherRow[])
    : [];
  const [user, successfulOrderCount] = session
    ? await Promise.all([
        prisma.user.findUnique({
          where: { id: session.sub },
          select: { id: true, createdAt: true },
        }),
        prisma.order.count({
          where: {
            userId: session.sub,
            status: { notIn: ["CANCELLED", "REFUNDED"] },
          },
        }),
      ])
    : [null, 0] as const;

  const available: ReturnType<typeof normalizeVoucher>[] = [];
  const unavailable: ReturnType<typeof normalizeUnavailable>[] = [];

  for (const voucher of visibleVouchers) {
    if (voucherTypeOf(voucher) === "PRIVATE_MANUAL_CODE") continue;
    if (!voucher.isActive) continue;
    if (voucher.expiresAt && voucher.expiresAt <= now) continue;
    if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) continue;
    if (userUsageCount(voucher) >= Math.max(1, voucher.usageLimitPerUser)) continue;

    if (voucher.startsAt > now) {
      unavailable.push(normalizeUnavailable(voucher, "Voucher belum berlaku", 0));
      continue;
    }
    if (subtotal < voucher.minimumOrder) {
      const shortfall = voucher.minimumOrder - subtotal;
      unavailable.push(
        normalizeUnavailable(
          voucher,
          `Belanja kurang Rp${new Intl.NumberFormat("id-ID").format(shortfall)} lagi`,
          shortfall,
        ),
      );
      continue;
    }
    if (voucherScopeOf(voucher) === "PRODUCT" && eligibleProductSubtotal(voucher) <= 0) {
      unavailable.push(normalizeUnavailable(voucher, "Tidak berlaku untuk produk ini", 0));
      continue;
    }

    const discount = discountFor(voucher);
    if (discount <= 0) {
      unavailable.push(
        normalizeUnavailable(voucher, "Voucher tidak memberikan potongan untuk pesanan ini", 0),
      );
      continue;
    }

    available.push(normalizeVoucher(voucher, discount));
  }

  available.sort((a, b) => {
    if (a.type !== b.type) return a.type.localeCompare(b.type);
    return b.discount - a.discount;
  });
  unavailable.sort((a, b) => (a.shortfall ?? 0) - (b.shortfall ?? 0));

  const byCode = new Map<string, VoucherRow>();
  for (const voucher of visibleVouchers) byCode.set(voucher.code, voucher);

  const privateVoucher = privateRequested
    ? ((await prisma.voucher.findUnique({
        where: { code: privateRequested },
      })) as VoucherRow | null)
    : null;

  let freeShippingApplied: ReturnType<typeof normalizeVoucher> | null = null;
  let productApplied: ReturnType<typeof normalizeVoucher> | null = null;
  let loyaltyApplied: ReturnType<typeof normalizeVoucher> | null = null;
  let privateApplied: ReturnType<typeof normalizeVoucher> | null = null;
  let freeShippingError: string | null = null;
  let productVoucherError: string | null = null;
  let loyaltyVoucherError: string | null = null;
  let privateVoucherError: string | null = null;
  let customerAuto = false;

  const bestByType = (type: VoucherTypeCode) =>
    available
      .filter((voucher) => voucher.type === type)
      .sort((a, b) => b.discount - a.discount)[0] ?? null;

  if (freeShippingRequested) {
    const result = validateVoucher(byCode.get(freeShippingRequested) ?? null, "PUBLIC_FREE_SHIPPING");
    freeShippingApplied = result.voucher;
    freeShippingError = result.error;
  } else if (input.autoApply) {
    freeShippingApplied = bestByType("PUBLIC_FREE_SHIPPING");
  }

  if (productRequested) {
    const result = validateVoucher(byCode.get(productRequested) ?? null, "PUBLIC_PRODUCT_DISCOUNT");
    productApplied = result.voucher;
    productVoucherError = result.error;
  } else if (input.autoApply) {
    productApplied = bestByType("PUBLIC_PRODUCT_DISCOUNT");
    customerAuto = productApplied !== null;
  }

  if (loyaltyRequested) {
    const result = validateVoucher(byCode.get(loyaltyRequested) ?? null, "LOYALTY_POINT_CLAIM");
    loyaltyApplied = result.voucher;
    loyaltyVoucherError = result.error;
  } else if (input.autoApply) {
    loyaltyApplied = bestByType("LOYALTY_POINT_CLAIM");
  }

  if (privateRequested) {
    const result = validateVoucher(privateVoucher, "PRIVATE_MANUAL_CODE");
    privateApplied = result.voucher;
    privateVoucherError = result.error;
  }

  const productDiscount = Math.min(
    subtotal,
    (productApplied?.discount ?? 0) +
      (loyaltyApplied?.discount ?? 0) +
      (privateApplied && privateApplied.discountScope === "PRODUCT" ? privateApplied.discount : 0),
  );
  const shippingDiscount = Math.min(
    shippingFee,
    (freeShippingApplied?.discount ?? 0) +
      (privateApplied && privateApplied.discountScope === "SHIPPING" ? privateApplied.discount : 0),
  );
  const finalShippingFee = Math.max(0, shippingFee - shippingDiscount);
  const total = Math.max(subtotal + finalShippingFee - productDiscount, 0);

  const customerApplied = productApplied ?? loyaltyApplied ?? freeShippingApplied;
  const manualApplied = privateApplied;
  const customerVoucherError =
    productVoucherError ?? loyaltyVoucherError ?? freeShippingError;
  const manualVoucherError = privateVoucherError;

  return NextResponse.json({
    subtotal,
    shipping_fee: finalShippingFee,
    shippingCost: finalShippingFee,
    originalShippingCost: shippingFee,
    discount: productDiscount,
    discountAmount: productDiscount,
    productDiscount,
    shippingDiscount,
    total,
    // Legacy fields mirror product voucher agar klien lama tidak break.
    auto_applied_voucher:
      productSlot.applied && productSlot.autoApplied
        ? {
            code: productSlot.applied.code,
            title: "Voucher member terpakai",
            description: describeDiscount(productSlot.applied.discount, productSlot.applied.kind),
            discount: productSlot.applied.discount,
            kind: productSlot.applied.kind,
          }
        : null,
    applied_voucher: productSlot.applied
      ? {
          ...productSlot.applied,
          title: "Voucher member terpakai",
          autoApplied: productSlot.autoApplied,
        }
      : null,
    applied_customer_voucher: productSlot.applied
      ? {
          ...productSlot.applied,
          title: "Voucher member terpakai",
          autoApplied: productSlot.autoApplied,
        }
      : null,
    applied_product_voucher: productSlot.applied
      ? {
          ...productSlot.applied,
          title: "Voucher diskon produk terpakai",
          autoApplied: productSlot.autoApplied,
        }
      : null,
    applied_shipping_voucher: shippingSlot.applied
      ? {
          ...shippingSlot.applied,
          title: "Voucher gratis ongkir terpakai",
          autoApplied: shippingSlot.autoApplied,
        }
      : null,
    applied_loyalty_voucher: loyaltySlot.applied
      ? {
          ...loyaltySlot.applied,
          title: "Voucher loyalty terpakai",
          autoApplied: loyaltySlot.autoApplied,
        }
      : null,
    applied_manual_voucher: manualApplied
      ? {
          ...manualApplied,
          title: "Voucher khusus terpakai",
          autoApplied: false,
        }
      : null,
    applied_free_shipping_voucher: freeShippingApplied,
    applied_product_voucher: productApplied,
    applied_loyalty_voucher: loyaltyApplied,
    applied_private_voucher: privateApplied,
    available_vouchers: available,
    unavailable_vouchers: unavailable,
    voucher_invalidated: Boolean(customerVoucherError ?? manualVoucherError),
    invalidated_message: customerVoucherError ?? manualVoucherError,
    customer_voucher_error: customerVoucherError,
    free_shipping_voucher_error: freeShippingError,
    product_voucher_error: productVoucherError,
    loyalty_voucher_error: loyaltyVoucherError,
    manual_voucher_error: manualVoucherError,
    private_voucher_error: privateVoucherError,
  });
}
