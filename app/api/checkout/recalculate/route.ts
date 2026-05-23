import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { cartItemSchema } from "@/lib/validation";
import { buildCheckoutItemsFromInventory } from "@/lib/checkout-items";
import {
  calcVoucherScopedDiscount,
  getVoucherDisabledReason,
  isVoucherUsageLimitReached,
  voucherScopeOf,
  voucherTypeOf,
  type VoucherUsageOrder,
} from "@/lib/voucher-helpers";
import {
  voucherSlotForKind,
  type VoucherSlotValue,
} from "@/lib/voucher-kind";

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
  freeShippingVoucherCode: z.string().trim().optional().nullable(),
  productVoucherCode: z.string().trim().optional().nullable(),
  shippingVoucherCode: z.string().trim().optional().nullable(),
  loyaltyVoucherCode: z.string().trim().optional().nullable(),
  manualVoucherCode: z.string().trim().optional().nullable(),
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
  description: string | null;
  discountPercent: number | null;
  discountAmount: number | null;
  maxDiscountAmount: number | null;
  minimumOrder: number;
  startsAt: Date;
  expiresAt: Date | null;
  maxUsage: number | null;
  usedCount: number;
  isActive: boolean;
  sourceType: VoucherSourceType;
  kind: VoucherKind;
  type: "PUBLIC_FREE_SHIPPING" | "PUBLIC_PRODUCT_DISCOUNT" | "LOYALTY_POINT_CLAIM" | "PRIVATE_MANUAL_CODE";
  visibility: "PUBLIC" | "PRIVATE" | "USER_OWNED";
  discountScope: "PRODUCT" | "SHIPPING";
  targetUser: "ALL_MEMBERS" | "NEW_MEMBER";
  newMemberMaxAccountAgeDays: number | null;
  newMemberRequireNoSuccessfulOrder: boolean;
  usageLimitPeriod: "NONE" | "LIFETIME" | "DAY" | "WEEK" | "MONTH";
  usageLimitPerUser: number;
  userId: string | null;
  eligibleUserIds: string[];
  eligibleProductIds: string[];
  eligibleCategoryIds: string[];
};

function describeDiscount(discount: number, kind?: VoucherKind) {
  if (kind === "FREE_SHIPPING") return "Gratis Ongkir";
  return `Hemat Rp${new Intl.NumberFormat("id-ID").format(discount)}`;
}

// Legacy voucher rows kadang punya `kind` salah (mis. loyalty voucher
// dengan `kind: PRODUCT_DISCOUNT` karena `/api/member/claim-voucher`
// historis tidak set `kind` → ambil default Prisma). Type column (`type`)
// adalah source of truth dari intent voucher karena selalu di-set
// explicit di setiap create. Derive effective kind dari type supaya
// slot resolver match dengan benar. Backfill migration sudah update
// row lama, tapi tetap defensive supaya tidak regress.
function effectiveKind(voucher: VoucherRow): VoucherKind {
  const type = voucherTypeOf(voucher);
  switch (type) {
    case "LOYALTY_POINT_CLAIM":
      return "LOYALTY_CLAIM";
    case "PUBLIC_FREE_SHIPPING":
      return "FREE_SHIPPING";
    case "PRIVATE_MANUAL_CODE":
      return "MANUAL_PRIVATE";
    case "PUBLIC_PRODUCT_DISCOUNT":
      return "PRODUCT_DISCOUNT";
    default:
      return voucher.kind;
  }
}

function normalizeVoucher(voucher: VoucherRow, discount: number) {
  const kind = effectiveKind(voucher);
  return {
    code: voucher.code,
    discount,
    description: voucher.description ?? describeDiscount(discount),
    minimumOrder: voucher.minimumOrder,
    expiresAt: voucher.expiresAt,
    sourceType: voucher.sourceType,
    kind,
    slot: voucherSlotForKind(kind),
    type: voucherTypeOf(voucher),
    discountScope: voucherScopeOf(voucher),
    targetUser: voucher.targetUser,
    status: "available" as const,
  };
}

function normalizeUnavailable(
  voucher: VoucherRow,
  reason: string,
  shortfall = 0,
) {
  const kind = effectiveKind(voucher);
  return {
    code: voucher.code,
    description: voucher.description ?? "",
    minimumOrder: voucher.minimumOrder,
    shortfall,
    expiresAt: voucher.expiresAt,
    reason,
    sourceType: voucher.sourceType,
    kind,
    slot: voucherSlotForKind(kind),
    type: voucherTypeOf(voucher),
    discountScope: voucherScopeOf(voucher),
    targetUser: voucher.targetUser,
    status: "unavailable" as const,
  };
}

function emptyVoucherPayload(shippingFee: number) {
  return {
    subtotal: 0,
    shipping_fee: shippingFee,
    discount: 0,
    productDiscount: 0,
    shippingDiscount: 0,
    total: shippingFee,
    auto_applied_voucher: null,
    applied_voucher: null,
    applied_customer_voucher: null,
    applied_product_voucher: null,
    applied_shipping_voucher: null,
    applied_free_shipping_voucher: null,
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

  const normalizeCode = (value?: string | null) => (value ?? "").trim().toUpperCase();
  // Legacy `voucherCode` / `customerVoucherCode` tetap diarahkan ke slot
  // product discount agar klien lama tidak break.
  const productRequested = normalizeCode(
    input.productVoucherCode ?? input.customerVoucherCode ?? input.voucherCode,
  );
  const shippingRequested = normalizeCode(input.shippingVoucherCode ?? input.freeShippingVoucherCode);
  const loyaltyRequested = normalizeCode(input.loyaltyVoucherCode);
  const manualRequested = normalizeCode(input.privateVoucherCode ?? input.manualVoucherCode);

  if (input.items.length === 0) {
    return NextResponse.json(emptyVoucherPayload(shippingFee));
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
        flashSaleEndsAt: true,
        stock: true,
        categoryId: true,
        weightGram: true,
        isActive: true,
        hasVariants: true,
        // Active Promo Toko items untuk apply diskon di checkout.
        // Filter inline pakai now() saat query — fresh per request.
        discountItems: {
          where: {
            isItemActive: true,
            discount: {
              isActive: true,
              startsAt: { lte: new Date() },
              endsAt: { gt: new Date() },
            },
          },
          select: {
            variantId: true,
            discountedPrice: true,
            discount: { select: { endsAt: true } },
          },
        },
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
  const productById = new Map(products.map((product) => [product.id, product]));
  const now = new Date();

  // Aturan Natalo: voucher CUSTOMER (member) HANYA untuk user login.
  // Guest tidak boleh dapat voucher publik. Kalau no session, list kosong.
  const customerVouchersRaw = session
    ? ((await prisma.voucher.findMany({
        where: {
          isActive: true,
          sourceType: "CUSTOMER",
          startsAt: { lte: now },
          OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
          AND: [{ OR: [{ userId: null }, { userId: session.sub }] }],
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

  // Aturan visibility (lihat /api/cart/vouchers): filter voucher yg user
  // sudah pernah pakai (per-user 1×). Voucher yg sudah dipakai TIDAK
  // muncul di available/unavailable, sekaligus mencegah auto-apply.
  let userUsedOrders: VoucherUsageOrder[] = [];
  if (session) {
    userUsedOrders = await prisma.order.findMany({
      where: {
        userId: session.sub,
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
    });
  }

  const customerVouchers = customerVouchersRaw.filter(
    (v) =>
      !isVoucherUsageLimitReached(v, userUsedOrders, now) &&
      (v.maxUsage === null || v.usedCount < v.maxUsage),
  );
  const userCtx = {
    isLoggedIn: Boolean(session),
    userId: session?.sub ?? null,
    createdAt: user?.createdAt ?? null,
    successfulOrderCount,
  };

  function eligibleProductSubtotal(voucher: {
    eligibleProductIds: string[];
    eligibleCategoryIds: string[];
  }) {
    const voucherProductIds = new Set(voucher.eligibleProductIds ?? []);
    const categoryIds = new Set(voucher.eligibleCategoryIds ?? []);
    if (voucherProductIds.size === 0 && categoryIds.size === 0) return subtotal;

    return checkoutItems.reduce((sum, item) => {
      const product = productById.get(item.productId);
      const productMatch = voucherProductIds.has(item.productId);
      const categoryMatch = product?.categoryId
        ? categoryIds.has(product.categoryId)
        : false;
      return productMatch || categoryMatch ? sum + item.price * item.quantity : sum;
    }, 0);
  }

  function checkoutVoucherDiscount(voucher: VoucherRow) {
    return calcVoucherScopedDiscount({
      subtotal,
      shippingFee,
      eligibleProductSubtotal: eligibleProductSubtotal(voucher),
      voucher,
    });
  }

  // Build available + unavailable list dari customer/member vouchers.
  const available: ReturnType<typeof normalizeVoucher>[] = [];
  const unavailable: ReturnType<typeof normalizeUnavailable>[] = [];

  for (const voucher of customerVouchers) {
    const disabledReason = getVoucherDisabledReason(voucher, subtotal, userCtx, now);
    if (disabledReason) {
      unavailable.push(normalizeUnavailable(voucher, disabledReason, 0));
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
    if (voucherScopeOf(voucher) === "SHIPPING" && shippingFee <= 0) {
      unavailable.push(
        normalizeUnavailable(voucher, "Pilih pengiriman untuk menggunakan gratis ongkir", 0),
      );
      continue;
    }
    if (voucherScopeOf(voucher) === "PRODUCT" && eligibleProductSubtotal(voucher) <= 0) {
      unavailable.push(
        normalizeUnavailable(voucher, "Voucher tidak berlaku untuk produk ini", 0),
      );
      continue;
    }

    const discount = checkoutVoucherDiscount(voucher);
    if (discount <= 0) {
      unavailable.push(
        normalizeUnavailable(voucher, "Voucher tidak memiliki potongan untuk checkout ini", 0),
      );
      continue;
    }

    available.push(normalizeVoucher(voucher, discount));
  }

  available.sort((a, b) => b.discount - a.discount);
  unavailable.sort((a, b) => (a.shortfall ?? 0) - (b.shortfall ?? 0));

  type NormalizedVoucher = ReturnType<typeof normalizeVoucher>;
  const slotKinds: Record<Exclude<VoucherSlotValue, "manual">, VoucherKind> = {
    product: "PRODUCT_DISCOUNT",
    shipping: "FREE_SHIPPING",
    loyalty: "LOYALTY_CLAIM",
  };
  const requestedBySlot: Record<Exclude<VoucherSlotValue, "manual">, string> = {
    product: productRequested,
    shipping: shippingRequested,
    loyalty: loyaltyRequested,
  };

  function resolveCustomerSlot(slot: Exclude<VoucherSlotValue, "manual">): {
    applied: NormalizedVoucher | null;
    error: string | null;
    autoApplied: boolean;
  } {
    const expectedKind = slotKinds[slot];
    const requestedCode = requestedBySlot[slot];

    if (requestedCode) {
      const inAvailable = available.find(
        (voucher) => voucher.code === requestedCode && voucher.kind === expectedKind,
      );
      if (inAvailable) return { applied: inAvailable, error: null, autoApplied: false };
      const requestedVoucher = customerVouchersRaw.find(
        (voucher) => voucher.code === requestedCode,
      );
      if (requestedVoucher && isVoucherUsageLimitReached(requestedVoucher, userUsedOrders, now)) {
        return { applied: null, error: "Kode voucher sudah pernah digunakan", autoApplied: false };
      }
      const inUnavailable = unavailable.find(
        (voucher) => voucher.code === requestedCode && voucher.kind === expectedKind,
      );
      return {
        applied: null,
        error: inUnavailable?.reason ?? "Voucher tidak bisa digunakan untuk slot ini",
        autoApplied: false,
      };
    }

    if (!input.autoApply) return { applied: null, error: null, autoApplied: false };

    const auto = available.find(
      (voucher) => voucher.kind === expectedKind && (voucher.discount > 0 || voucher.kind === "FREE_SHIPPING"),
    );
    return { applied: auto ?? null, error: null, autoApplied: Boolean(auto) };
  }

  const productSlot = resolveCustomerSlot("product");
  const shippingSlot = resolveCustomerSlot("shipping");
  const loyaltySlot = resolveCustomerSlot("loyalty");

  let manualVoucherError: string | null = null;
  let manualApplied: NormalizedVoucher | null = null;
  if (manualRequested) {
    const manualVoucher = (await prisma.voucher.findUnique({
      where: { code: manualRequested },
    })) as VoucherRow | null;

    if (!session) {
      manualVoucherError = "Login dulu untuk menggunakan voucher.";
    } else if (!manualVoucher || !manualVoucher.isActive) {
      manualVoucherError = "Kode voucher tidak valid.";
    } else if (isVoucherUsageLimitReached(manualVoucher, userUsedOrders, now)) {
      manualVoucherError = "Kode voucher sudah pernah digunakan";
    } else if (
      manualVoucher.sourceType !== "SELLER_MANUAL" ||
      voucherTypeOf(manualVoucher) !== "PRIVATE_MANUAL_CODE"
    ) {
      manualVoucherError =
        "Kode ini bukan voucher manual/private. Pilih voucher member lewat daftar voucher.";
    } else if (manualVoucher.userId && manualVoucher.userId !== session.sub) {
      manualVoucherError = "Kode voucher ini tidak tersedia untuk akun kamu";
    } else if (
      manualVoucher.eligibleUserIds.length > 0 &&
      !manualVoucher.eligibleUserIds.includes(session.sub)
    ) {
      manualVoucherError = "Kode voucher ini tidak tersedia untuk akun kamu";
    } else if (manualVoucher.expiresAt && manualVoucher.expiresAt <= now) {
      manualVoucherError = "Kode voucher sudah berakhir";
    } else if (manualVoucher.startsAt > now) {
      manualVoucherError = "Voucher belum berlaku.";
    } else if (
      manualVoucher.maxUsage !== null &&
      manualVoucher.usedCount >= manualVoucher.maxUsage
    ) {
      manualVoucherError = "Voucher sudah mencapai batas penggunaan.";
    } else if (subtotal < manualVoucher.minimumOrder) {
      const shortfall = manualVoucher.minimumOrder - subtotal;
      manualVoucherError = `Belanja kurang Rp${new Intl.NumberFormat("id-ID").format(shortfall)} lagi`;
    } else if (
      voucherScopeOf(manualVoucher) === "PRODUCT" &&
      eligibleProductSubtotal(manualVoucher) <= 0
    ) {
      manualVoucherError = "Voucher tidak berlaku untuk produk ini";
    } else {
      const discount = checkoutVoucherDiscount(manualVoucher);
      if (discount <= 0) {
        manualVoucherError = "Voucher tidak memberikan potongan untuk pesanan ini.";
      } else {
        manualApplied = normalizeVoucher(manualVoucher, discount);
      }
    }
  }

  const appliedDiscounts = [
    productSlot.applied,
    shippingSlot.applied,
    loyaltySlot.applied,
    manualApplied,
  ].filter(Boolean) as NormalizedVoucher[];
  const productDiscount = Math.min(
    appliedDiscounts
      .filter((voucher) => voucher.discountScope === "PRODUCT")
      .reduce((sum, voucher) => sum + voucher.discount, 0),
    subtotal,
  );
  const shippingDiscount = Math.min(
    appliedDiscounts
      .filter((voucher) => voucher.discountScope === "SHIPPING")
      .reduce((sum, voucher) => sum + voucher.discount, 0),
    shippingFee,
  );
  const totalDiscount = productDiscount + shippingDiscount;
  const total = Math.max(subtotal + shippingFee - totalDiscount, 0);

  return NextResponse.json({
    subtotal,
    shipping_fee: shippingFee,
    discount: totalDiscount,
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
    applied_free_shipping_voucher: shippingSlot.applied
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
    available_vouchers: available,
    unavailable_vouchers: unavailable,
    voucher_invalidated: Boolean(
      productSlot.error || shippingSlot.error || loyaltySlot.error,
    ),
    invalidated_message: productSlot.error ?? shippingSlot.error ?? loyaltySlot.error,
    customer_voucher_error: productSlot.error ?? shippingSlot.error ?? loyaltySlot.error,
    product_voucher_error: productSlot.error,
    shipping_voucher_error: shippingSlot.error,
    loyalty_voucher_error: loyaltySlot.error,
    manual_voucher_error: manualVoucherError,
  });
}
