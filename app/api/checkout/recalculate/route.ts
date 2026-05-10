import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { cartItemSchema } from "@/lib/validation";

const recalculateSchema = z.object({
  items: z.array(cartItemSchema).default([]),
  shipping_fee: z.number().int().nonnegative().optional(),
  shippingCost: z.number().int().nonnegative().optional(),
  voucherCode: z.string().trim().optional().nullable(),
  autoApply: z.boolean().default(true),
  address: z
    .object({
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

type VoucherRow = {
  code: string;
  description: string | null;
  discountPercent: number | null;
  discountAmount: number | null;
  minimumOrder: number;
  expiresAt: Date | null;
  maxUsage: number | null;
  usedCount: number;
};

function calcDiscount(
  subtotal: number,
  voucher: Pick<VoucherRow, "discountPercent" | "discountAmount">,
) {
  let discount = 0;
  if (voucher.discountPercent) discount += Math.floor((subtotal * voucher.discountPercent) / 100);
  if (voucher.discountAmount) discount += voucher.discountAmount;
  return Math.min(discount, subtotal);
}

function describeDiscount(discount: number) {
  return `Hemat Rp${new Intl.NumberFormat("id-ID").format(discount)}`;
}

function normalizeVoucher(voucher: VoucherRow, discount: number) {
  return {
    code: voucher.code,
    discount,
    description: voucher.description ?? describeDiscount(discount),
    minimumOrder: voucher.minimumOrder,
    expiresAt: voucher.expiresAt,
    status: "available" as const,
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

  if (input.items.length === 0) {
    return NextResponse.json({
      subtotal: 0,
      shipping_fee: shippingFee,
      discount: 0,
      total: shippingFee,
      auto_applied_voucher: null,
      applied_voucher: null,
      available_vouchers: [],
      unavailable_vouchers: [],
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
        isActive: true,
      },
    }),
    variantIds.length
      ? prisma.productVariant.findMany({
          where: { id: { in: variantIds }, deletedAt: null, isActive: true },
          select: { id: true, productId: true, price: true, stock: true, weightGram: true },
        })
      : Promise.resolve([]),
  ]);

  const checkoutItems: Array<{ price: number; quantity: number }> = [];
  const stockErrors: string[] = [];

  for (const requested of requestedMap.values()) {
    const product = products.find((row) => row.id === requested.productId);
    if (!product || !product.isActive) {
      stockErrors.push("Produk di keranjang sudah tidak tersedia.");
      continue;
    }

    if (requested.variantId) {
      const variant = variants.find((row) => row.id === requested.variantId);
      if (!variant) {
        stockErrors.push(`Varian produk "${product.name}" sudah tidak tersedia.`);
        continue;
      }
      if (variant.stock < requested.quantity) {
        stockErrors.push(`"${product.name} (${requested.variantLabel ?? ""})" hanya tersedia ${variant.stock} unit.`);
        continue;
      }
      checkoutItems.push({ price: variant.price, quantity: requested.quantity });
      continue;
    }

    if (product.stock < requested.quantity) {
      stockErrors.push(`${product.name} hanya tersedia ${product.stock}, sedangkan keranjang berisi ${requested.quantity}.`);
      continue;
    }

    checkoutItems.push({
      price:
        product.discountPrice !== null && product.discountPrice < product.price
          ? product.discountPrice
          : product.price,
      quantity: requested.quantity,
    });
  }

  if (stockErrors.length > 0) {
    return NextResponse.json({ message: stockErrors.join(" ") }, { status: 409 });
  }

  const subtotal = checkoutItems.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const now = new Date();
  const voucherOwnership = session
    ? [{ userId: null }, { userId: session.sub }]
    : [{ userId: null }];

  const vouchers = await prisma.voucher.findMany({
    where: {
      isActive: true,
      startsAt: { lte: now },
      OR: [
        { expiresAt: null },
        { expiresAt: { gt: now } },
      ],
      AND: [{ OR: voucherOwnership }],
    },
    orderBy: { createdAt: "desc" },
  });

  const available = [];
  const unavailable = [];

  for (const voucher of vouchers) {
    if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) {
      unavailable.push({
        code: voucher.code,
        description: "Batas penggunaan sudah tercapai",
        reason: "Voucher sudah mencapai batas penggunaan",
        minimumOrder: voucher.minimumOrder,
        shortfall: 0,
        expiresAt: voucher.expiresAt,
        status: "unavailable" as const,
      });
      continue;
    }

    if (subtotal < voucher.minimumOrder) {
      const shortfall = voucher.minimumOrder - subtotal;
      unavailable.push({
        code: voucher.code,
        description: `Min. belanja Rp${new Intl.NumberFormat("id-ID").format(voucher.minimumOrder)}`,
        reason: `Belanja kurang Rp${new Intl.NumberFormat("id-ID").format(shortfall)} lagi`,
        minimumOrder: voucher.minimumOrder,
        shortfall,
        expiresAt: voucher.expiresAt,
        status: "unavailable" as const,
      });
      continue;
    }

    const discount = calcDiscount(subtotal, voucher);
    if (discount <= 0) {
      unavailable.push({
        code: voucher.code,
        description: voucher.description ?? "Voucher belum bisa dipakai",
        reason: "Voucher tidak memiliki potongan untuk checkout ini",
        minimumOrder: voucher.minimumOrder,
        shortfall: 0,
        expiresAt: voucher.expiresAt,
        status: "unavailable" as const,
      });
      continue;
    }

    available.push(normalizeVoucher(voucher, discount));
  }

  available.sort((a, b) => b.discount - a.discount);
  unavailable.sort((a, b) => (a.shortfall ?? 0) - (b.shortfall ?? 0));

  const requestedCode = input.voucherCode?.trim().toUpperCase() || "";
  const requestedAvailable = requestedCode
    ? available.find((voucher) => voucher.code === requestedCode)
    : null;
  const requestedUnavailable = requestedCode
    ? unavailable.find((voucher) => voucher.code === requestedCode)
    : null;
  const invalidatedMessage =
    requestedCode && !requestedAvailable
      ? requestedUnavailable?.reason ?? "Voucher tidak bisa digunakan untuk pilihan ini"
      : null;

  const applied = requestedAvailable ?? (input.autoApply ? available[0] : null) ?? null;
  const appliedAuto = Boolean(applied && !requestedAvailable);
  const discount = applied?.discount ?? 0;
  const total = Math.max(subtotal + shippingFee - discount, 0);

  return NextResponse.json({
    subtotal,
    shipping_fee: shippingFee,
    discount,
    total,
    auto_applied_voucher:
      applied && appliedAuto
        ? {
            code: applied.code,
            title: `${applied.code} terpakai`,
            description: describeDiscount(applied.discount),
            discount: applied.discount,
          }
        : null,
    applied_voucher: applied
      ? {
          ...applied,
          title: `${applied.code} terpakai`,
          autoApplied: appliedAuto,
        }
      : null,
    available_vouchers: available,
    unavailable_vouchers: unavailable,
    voucher_invalidated: Boolean(invalidatedMessage),
    invalidated_message: invalidatedMessage,
  });
}
