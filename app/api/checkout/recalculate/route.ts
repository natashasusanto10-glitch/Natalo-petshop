import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { cartItemSchema } from "@/lib/validation";

/**
 * Aturan voucher checkout (lihat CLAUDE.md - Voucher business rules):
 * - Maks 2 voucher per checkout
 * - Maks 1 voucher CUSTOMER (publik / milik user) + 1 voucher SELLER_MANUAL
 * - Voucher SELLER_MANUAL TIDAK muncul di daftar publik (filtered)
 * - SELLER_MANUAL hanya bisa via input kode manual
 * - Semua validasi & total dihitung di backend (source of truth)
 */

const recalculateSchema = z.object({
  items: z.array(cartItemSchema).default([]),
  shipping_fee: z.number().int().nonnegative().optional(),
  shippingCost: z.number().int().nonnegative().optional(),
  // Legacy single-code field (backwards compat dgn klien lama)
  voucherCode: z.string().trim().optional().nullable(),
  // New dual-slot fields
  customerVoucherCode: z.string().trim().optional().nullable(),
  manualVoucherCode: z.string().trim().optional().nullable(),
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

type VoucherSourceType = "CUSTOMER" | "SELLER_MANUAL";

type VoucherRow = {
  code: string;
  description: string | null;
  discountPercent: number | null;
  discountAmount: number | null;
  minimumOrder: number;
  startsAt: Date;
  expiresAt: Date | null;
  maxUsage: number | null;
  usedCount: number;
  isActive: boolean;
  sourceType: VoucherSourceType;
  userId: string | null;
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
    sourceType: voucher.sourceType,
    status: "available" as const,
  };
}

function normalizeUnavailable(
  voucher: VoucherRow,
  reason: string,
  shortfall = 0,
) {
  return {
    code: voucher.code,
    description: voucher.description ?? "",
    minimumOrder: voucher.minimumOrder,
    shortfall,
    expiresAt: voucher.expiresAt,
    reason,
    sourceType: voucher.sourceType,
    status: "unavailable" as const,
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

  // Normalize codes — uppercase + trim. Legacy `voucherCode` field di-treat
  // sebagai customer code (backwards compat).
  const customerRequested = (
    input.customerVoucherCode ?? input.voucherCode ?? ""
  )
    .trim()
    .toUpperCase();
  const manualRequested = (input.manualVoucherCode ?? "").trim().toUpperCase();

  if (input.items.length === 0) {
    return NextResponse.json({
      subtotal: 0,
      shipping_fee: shippingFee,
      discount: 0,
      total: shippingFee,
      // Legacy fields (backwards compat — selalu reflect customer voucher)
      auto_applied_voucher: null,
      applied_voucher: null,
      // New dual-slot fields
      applied_customer_voucher: null,
      applied_manual_voucher: null,
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

  // Aturan Natalo: voucher CUSTOMER (member) HANYA untuk user login.
  // Guest tidak boleh dapat voucher publik. Kalau no session, list kosong.
  const customerVouchers = session
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

  // Manual seller voucher — hanya kalau di-request via kode
  const manualVoucher = manualRequested
    ? ((await prisma.voucher.findUnique({
        where: { code: manualRequested },
      })) as VoucherRow | null)
    : null;

  // Validasi tipe voucher manual: HARUS SELLER_MANUAL. Kalau pakai customer
  // code di slot manual, return error.
  let manualVoucherError: string | null = null;
  let manualApplied: ReturnType<typeof normalizeVoucher> | null = null;

  if (manualRequested) {
    if (!manualVoucher || !manualVoucher.isActive) {
      manualVoucherError = "Kode voucher tidak valid.";
    } else if (manualVoucher.sourceType !== "SELLER_MANUAL") {
      // Sesuai aturan: input kode manual HANYA untuk voucher SELLER_MANUAL.
      // Customer voucher (publik / claim user) harus dipilih lewat daftar.
      manualVoucherError =
        "Kode ini bukan voucher manual penjual. Pilih lewat daftar voucher pembeli.";
    } else if (manualVoucher.expiresAt && manualVoucher.expiresAt <= now) {
      manualVoucherError = "Voucher sudah kedaluwarsa.";
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
    } else {
      const discount = calcDiscount(subtotal, manualVoucher);
      if (discount <= 0) {
        manualVoucherError = "Voucher tidak memberikan potongan untuk pesanan ini.";
      } else {
        manualApplied = normalizeVoucher(manualVoucher, discount);
      }
    }
  }

  // Guard defensif: kalau input legacy `voucherCode` & `customerVoucherCode`
  // dikirim DUA-DUA dgn nilai berbeda → klien mencoba apply 2 customer
  // voucher sekaligus. Tolak dengan pesan sesuai spec.
  const legacyCustomer = (input.voucherCode ?? "").trim().toUpperCase();
  const dualCustomerProvided =
    !!input.customerVoucherCode &&
    !!legacyCustomer &&
    legacyCustomer !== (input.customerVoucherCode ?? "").trim().toUpperCase();
  if (dualCustomerProvided) {
    return NextResponse.json(
      { message: "Hanya 1 voucher pembeli yang dapat digunakan" },
      { status: 400 },
    );
  }

  // Build available + unavailable list dari customer vouchers
  const available: ReturnType<typeof normalizeVoucher>[] = [];
  const unavailable: ReturnType<typeof normalizeUnavailable>[] = [];

  for (const voucher of customerVouchers) {
    if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) {
      unavailable.push(
        normalizeUnavailable(voucher, "Voucher sudah mencapai batas penggunaan", 0),
      );
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

    const discount = calcDiscount(subtotal, voucher);
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

  // Resolve customer voucher slot
  let customerVoucherError: string | null = null;
  let customerApplied: ReturnType<typeof normalizeVoucher> | null = null;
  let customerAuto = false;

  if (customerRequested) {
    const inAvailable = available.find((v) => v.code === customerRequested);
    if (inAvailable) {
      customerApplied = inAvailable;
    } else {
      const inUnavailable = unavailable.find((v) => v.code === customerRequested);
      // Cek apakah code ada tapi sourceType salah (manual code di-input ke
      // slot customer)
      const wrongType = customerVouchers.length === 0
        ? await prisma.voucher.findUnique({ where: { code: customerRequested } })
        : null;
      if (wrongType?.sourceType === "SELLER_MANUAL") {
        customerVoucherError =
          "Kode ini adalah voucher manual penjual. Masukkan lewat input kode manual.";
      } else {
        customerVoucherError =
          inUnavailable?.reason ?? "Voucher tidak bisa digunakan untuk pilihan ini";
      }
    }
  } else if (input.autoApply && available.length > 0) {
    // Auto-apply best customer voucher kalau user belum pilih
    customerApplied = available[0];
    customerAuto = true;
  }

  // Combine discount: customer + manual, capped at subtotal
  const customerDiscount = customerApplied?.discount ?? 0;
  const manualDiscount = manualApplied?.discount ?? 0;
  const totalDiscount = Math.min(customerDiscount + manualDiscount, subtotal);
  const total = Math.max(subtotal + shippingFee - totalDiscount, 0);

  return NextResponse.json({
    subtotal,
    shipping_fee: shippingFee,
    discount: totalDiscount,
    total,
    // Legacy fields (mirror customer voucher) — agar klien lama tidak break
    auto_applied_voucher:
      customerApplied && customerAuto
        ? {
            code: customerApplied.code,
            title: `${customerApplied.code} terpakai`,
            description: describeDiscount(customerApplied.discount),
            discount: customerApplied.discount,
          }
        : null,
    applied_voucher: customerApplied
      ? {
          ...customerApplied,
          title: `${customerApplied.code} terpakai`,
          autoApplied: customerAuto,
        }
      : null,
    // New dual-slot fields
    applied_customer_voucher: customerApplied
      ? {
          ...customerApplied,
          title: `${customerApplied.code} terpakai`,
          autoApplied: customerAuto,
        }
      : null,
    applied_manual_voucher: manualApplied
      ? {
          ...manualApplied,
          title: `${manualApplied.code} terpakai`,
          autoApplied: false,
        }
      : null,
    available_vouchers: available,
    unavailable_vouchers: unavailable,
    voucher_invalidated: Boolean(customerVoucherError),
    invalidated_message: customerVoucherError,
    customer_voucher_error: customerVoucherError,
    manual_voucher_error: manualVoucherError,
  });
}
