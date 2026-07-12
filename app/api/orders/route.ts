import { after, NextResponse } from "next/server";
import { Prisma } from "@prisma/client";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { createOrderNumber } from "@/lib/format";
import { createOrderSchema } from "@/lib/validation";
import {
  buildCheckoutItemsFromInventory,
  type CheckedOutItem,
} from "@/lib/checkout-items";
import { InvalidCustomerSessionError, resolveOrderIdentity } from "@/lib/order-identity";
import { buildOrderDetailPath, buildOrderSuccessUrl, createTrackingToken } from "@/lib/order-detail";
import { debitWallet, getOrCreateWallet } from "@/lib/refund-wallet";
import { withSerializationRetry, isSerializationFailure } from "@/lib/db-retry";
import { SELF_PICKUP_METHOD, SELF_PICKUP_STORE } from "@/lib/self-pickup";
// Catatan: notifikasi order via WhatsApp sudah dihapus (per keputusan
// product owner). Customer dapat info order via email + push notification.
import {
  calcVoucherScopedDiscount,
  getNewMemberVoucherDisabledReason,
  isVoucherUsageLimitReached,
  voucherScopeOf,
  voucherTypeOf,
  type VoucherTypeCode,
} from "@/lib/voucher-helpers";
import { cartMatchesVoucherScope, voucherMatchesProduct } from "@/lib/voucher-eligibility";

class StockConflictError extends Error {
  status = 409;
}

class VoucherValidationError extends Error {
  status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}

function itemLabel(item: Pick<CheckedOutItem, "name" | "variantLabel">) {
  return `${item.name}${item.variantLabel ? ` (${item.variantLabel})` : ""}`;
}

async function createMidtransPayment(order: { orderNumber: string; trackingToken?: string | null; total: number; customerName: string; customerEmail?: string | null; customerPhone: string }) {
  const serverKey = process.env.MIDTRANS_SERVER_KEY;
  if (!serverKey) throw new Error("MIDTRANS_SERVER_KEY belum diisi.");

  const isProduction = process.env.MIDTRANS_IS_PRODUCTION === "true";
  const baseUrl = isProduction ? "https://app.midtrans.com" : "https://app.sandbox.midtrans.com";
  const auth = Buffer.from(`${serverKey}:`).toString("base64");

  const res = await fetch(`${baseUrl}/snap/v1/transactions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Basic ${auth}`,
    },
    body: JSON.stringify({
      transaction_details: {
        order_id: order.orderNumber,
        gross_amount: order.total,
      },
      customer_details: {
        first_name: order.customerName,
        email: order.customerEmail || undefined,
        phone: order.customerPhone,
      },
      // Restrict ke metode yang kita support — JANGAN ada COD
      enabled_payments: [
        "bca_va",
        "bni_va",
        "bri_va",
        "mandiri_bill",
        "permata_va",
        "gopay",
        "shopeepay",
        "qris",
      ],
      callbacks: {
        finish: buildOrderSuccessUrl(order.orderNumber, order.trackingToken),
      },
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Midtrans error: ${text}`);
  }

  const data = await res.json();
  return { reference: data.token as string, url: data.redirect_url as string };
}

export async function POST(request: Request) {
  const json = await request.json();
  const parsed = createOrderSchema.safeParse(json);

  if (!parsed.success) {
    if (parsed.error.flatten().fieldErrors.shippingAreaId) {
      return NextResponse.json(
        {
          message:
            "Alamat pengiriman belum valid. Mohon pilih ulang kota/kecamatan dari daftar alamat.",
        },
        { status: 400 },
      );
    }
    return NextResponse.json({ message: "Data checkout tidak valid.", errors: parsed.error.flatten() }, { status: 400 });
  }

  const input = parsed.data;
  // Pisahkan item variant vs non-variant
  // Key untuk dedup: "productId:variantId" atau "productId:" kalau tidak ada variant
  const requestedMap = new Map<string, { productId: string; variantId?: string | null; variantLabel?: string | null; quantity: number }>();
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

  const productIds = [...new Set([...requestedMap.values()].map((i) => i.productId))];
  const variantIds = [...new Set([...requestedMap.values()].map((i) => i.variantId).filter(Boolean))] as string[];

  const [products, variants] = await Promise.all([
    prisma.product.findMany({
      where: { id: { in: productIds } },
      select: {
        id: true,
        name: true,
        price: true,
        discountPrice: true,
        // Flash Sale window — dipakai resolveActiveDiscount untuk hitung
        // harga efektif. Tanpa ini order POST abaikan flash sale.
        flashSaleEndsAt: true,
        stock: true,
        weightGram: true,
        categoryId: true,
        brandId: true,
        category: { select: { slug: true } },
        isActive: true,
        hasVariants: true,
        // Active Promo Toko items — HARUS di-fetch supaya order creation
        // apply diskon yang sama dengan checkout preview (recalculate).
        // Tanpa ini: customer lihat harga promo di app, tapi order
        // di-charge harga penuh → overcharge + admin nagih sisa yang
        // sebenarnya sudah ke-cover. Filter inline now() = fresh per request.
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

  // SINGLE SOURCE OF TRUTH untuk harga checkout — helper yang SAMA dipakai
  // /api/checkout/recalculate. Apply Flash Sale + Promo Toko (discountItems)
  // via singleProductPrice/variantPrice. SEBELUMNYA order POST hand-roll
  // sendiri dan cuma cek discountPrice → abaikan Promo Toko + Flash Sale →
  // harga di order != harga di preview → customer overcharge + admin nagih
  // sisa yang sebenarnya sudah ke-cover saldo. Sekarang dijamin konsisten.
  const { checkoutItems, stockErrors } = buildCheckoutItemsFromInventory({
    requestedItems: requestedMap.values(),
    products,
    variants,
  });

  if (stockErrors.length > 0) {
    return NextResponse.json({ message: stockErrors.join(" ") }, { status: 409 });
  }

  const subtotal = checkoutItems.reduce((sum, item) => sum + item.price * item.quantity, 0);

  try {
    const customerSession = await getSession("CUSTOMER");
    const sessionUserId = customerSession?.sub ?? null;
    const { effectiveUserId } = await resolveOrderIdentity({
      sessionUserId,
      checkout: {
        customerName: input.customerName,
        customerPhone: input.customerPhone,
        customerEmail: input.customerEmail || null,
      },
      findSessionUser(userId) {
        return prisma.user.findUnique({
          where: { id: userId },
          select: { id: true },
        });
      },
      findGuestUser({ phone, email }) {
        // SECURITY: Hanya match user TANPA passwordHash (pure guest placeholder).
        // Sebelumnya: guest checkout dgn email/phone milik registered user akan
        // auto-attach ke akun mereka → attacker bisa "claim" voucher private
        // user lain dgn isi email/HP korban di guest checkout (effectiveUserId
        // di-bind ke korban, voucher.userId === effectiveUserId pass).
        //
        // Real accounts (passwordHash != null) WAJIB login untuk attach order.
        return prisma.user.findFirst({
          where: {
            passwordHash: null,
            OR: [
              { phone },
              email ? { email } : undefined,
            ].filter(Boolean) as { phone?: string; email?: string }[],
          },
          select: { id: true },
        });
      },
      createGuestUser(checkout) {
        return prisma.user.create({
          data: {
            name: checkout.customerName,
            phone: checkout.customerPhone,
            email: checkout.customerEmail || null,
          },
          select: { id: true },
        });
      },
    });

    const requestedCodes = [
      input.voucherCode,
      input.freeShippingVoucherCode,
      input.productVoucherCode,
      input.loyaltyVoucherCode,
      input.manualVoucherCode,
      input.privateVoucherCode,
    ].filter((code) => code?.trim());

    if (requestedCodes.length > 0 && !customerSession) {
      throw new VoucherValidationError("Login dulu untuk menggunakan voucher member.", 401);
    }

    const isSelfPickup =
      input.orderType === SELF_PICKUP_METHOD ||
      input.shippingMethod === SELF_PICKUP_METHOD;
    const originalShippingCost = isSelfPickup ? 0 : input.shippingCost;
    const productById = new Map(products.map((product) => [product.id, product]));

    const cartProductInputs = checkoutItems.map((item) => {
      const product = productById.get(item.productId);
      return {
        id: item.productId,
        categoryId: product?.categoryId ?? null,
        categorySlug: product?.category?.slug ?? null,
        brandId: product?.brandId ?? null,
      };
    });

    const [userUsedOrders, voucherUser, successfulOrderCount] = await Promise.all([
      prisma.order.findMany({
        where: {
          userId: effectiveUserId,
          OR: [
            { voucherCode: { not: null } },
            { manualVoucherCode: { not: null } },
            { freeShippingVoucherCode: { not: null } },
            { productVoucherCode: { not: null } },
            { shippingVoucherCode: { not: null } },
            { loyaltyVoucherCode: { not: null } },
            { privateVoucherCode: { not: null } },
          ],
        },
        select: {
          createdAt: true,
          voucherCode: true,
          manualVoucherCode: true,
          freeShippingVoucherCode: true,
          productVoucherCode: true,
          shippingVoucherCode: true,
          loyaltyVoucherCode: true,
          privateVoucherCode: true,
        },
      }),
      prisma.user.findUnique({
        where: { id: effectiveUserId },
        select: { id: true, createdAt: true },
      }),
      prisma.order.count({
        where: {
          userId: effectiveUserId,
          status: { notIn: ["CANCELLED", "REFUNDED"] },
        },
      }),
    ]);
    const voucherUserCtx = {
      isLoggedIn: Boolean(customerSession),
      userId: customerSession?.sub ?? null,
      createdAt: voucherUser?.createdAt ?? null,
      successfulOrderCount,
    };

    type AppliedVoucher = {
      id: string;
      maxUsage: number | null;
      usageLimitPerUser: number | null;
      usageLimitPeriod: string | null;
      code: string;
      type: string;
      scope: string;
      discount: number;
    };
    let appliedFreeShippingVoucher: AppliedVoucher | null = null;
    let appliedProductVoucher: AppliedVoucher | null = null;
    let appliedLoyaltyVoucher: AppliedVoucher | null = null;
    let appliedPrivateVoucher: AppliedVoucher | null = null;

    function eligibleProductSubtotal(voucher: {
      eligibleProductIds: string[];
      eligibleCategoryIds: string[];
      eligibleBrandIds: string[];
    }) {
      return checkoutItems.reduce((sum, item) => {
        const product = productById.get(item.productId);
        const matches = voucherMatchesProduct(voucher, {
          id: item.productId,
          categoryId: product?.categoryId ?? null,
          categorySlug: product?.category?.slug ?? null,
          brandId: product?.brandId ?? null,
        });
        return matches ? sum + item.price * item.quantity : sum;
      }, 0);
    }

    async function validateAndCalcVoucher(
      code: string,
      expectedType: VoucherTypeCode,
    ): Promise<{ voucher: AppliedVoucher; addedDiscount: number } | null> {
      const now = new Date();
      const voucher = await prisma.voucher.findUnique({
        where: { code: code.trim().toUpperCase() },
      });
      if (!voucher || !voucher.isActive) {
        throw new VoucherValidationError(
          "Kode voucher tidak valid atau tidak tersedia untuk akun ini",
        );
      }
      const voucherType = voucherTypeOf(voucher);
      if (voucherType !== expectedType) {
        throw new VoucherValidationError(
          expectedType === "PRIVATE_MANUAL_CODE"
            ? "Kode voucher khusus tidak valid untuk akun ini."
            : "Voucher tidak sesuai dengan slot yang dipilih.",
        );
      }
      if (isVoucherUsageLimitReached(voucher, userUsedOrders, now)) {
        throw new VoucherValidationError("Kode voucher sudah pernah digunakan");
      }
      if (voucher.expiresAt && voucher.expiresAt <= now) {
        throw new VoucherValidationError("Voucher sudah berakhir");
      }
      if (voucher.startsAt > now) {
        throw new VoucherValidationError("Voucher belum berlaku");
      }
      const newMemberReason = getNewMemberVoucherDisabledReason(
        voucher,
        voucherUserCtx,
        now,
      );
      if (newMemberReason) {
        throw new VoucherValidationError(newMemberReason);
      }
      if (voucher.maxUsage !== null && voucher.usedCount >= voucher.maxUsage) {
        throw new VoucherValidationError("Kuota voucher sudah habis");
      }
      if (voucher.minimumOrder > subtotal) {
        throw new VoucherValidationError("Minimal belanja belum terpenuhi");
      }
      if (voucher.userId && voucher.userId !== effectiveUserId) {
        throw new VoucherValidationError(
          "Kode voucher ini tidak tersedia untuk akun kamu",
        );
      }
      if (
        voucher.visibility === "PRIVATE" &&
        voucher.eligibleUserIds.length > 0 &&
        !voucher.eligibleUserIds.includes(effectiveUserId)
      ) {
        throw new VoucherValidationError(
          "Kode voucher ini tidak tersedia untuk akun kamu",
        );
      }
      if (!cartMatchesVoucherScope(voucher, cartProductInputs)) {
        throw new VoucherValidationError(
          "Voucher tidak berlaku untuk produk ini",
        );
      }
      const added = calcVoucherScopedDiscount({
        subtotal,
        shippingFee: originalShippingCost,
        eligibleProductSubtotal: eligibleProductSubtotal(voucher),
        voucher,
      });
      if (added <= 0) {
        throw new VoucherValidationError(
          "Voucher tidak memberikan potongan untuk pesanan ini",
        );
      }
      return {
        voucher: {
          id: voucher.id,
          maxUsage: voucher.maxUsage,
          usageLimitPerUser: voucher.usageLimitPerUser,
          usageLimitPeriod: voucher.usageLimitPeriod,
          code: voucher.code,
          type: voucherType,
          scope: voucherScopeOf(voucher),
          discount: added,
        },
        addedDiscount: added,
      };
    }

    const freeShippingCode = input.freeShippingVoucherCode?.trim();
    const productCode = (input.productVoucherCode ?? input.voucherCode)?.trim();
    const loyaltyCode = input.loyaltyVoucherCode?.trim();
    const privateCode = (input.privateVoucherCode ?? input.manualVoucherCode)?.trim();

    if (freeShippingCode) {
      const result = await validateAndCalcVoucher(
        freeShippingCode,
        "PUBLIC_FREE_SHIPPING",
      );
      appliedFreeShippingVoucher = result?.voucher ?? null;
    }
    if (productCode) {
      const result = await validateAndCalcVoucher(
        productCode,
        "PUBLIC_PRODUCT_DISCOUNT",
      );
      appliedProductVoucher = result?.voucher ?? null;
    }
    if (loyaltyCode) {
      const result = await validateAndCalcVoucher(
        loyaltyCode,
        "LOYALTY_POINT_CLAIM",
      );
      appliedLoyaltyVoucher = result?.voucher ?? null;
    }
    if (privateCode) {
      const result = await validateAndCalcVoucher(
        privateCode,
        "PRIVATE_MANUAL_CODE",
      );
      appliedPrivateVoucher = result?.voucher ?? null;
    }

    const productDiscount = Math.min(
      subtotal,
      (appliedProductVoucher?.discount ?? 0) +
        (appliedLoyaltyVoucher?.discount ?? 0) +
        (appliedPrivateVoucher?.scope === "PRODUCT"
          ? appliedPrivateVoucher.discount
          : 0),
    );
    const shippingDiscount = Math.min(
      originalShippingCost,
      (appliedFreeShippingVoucher?.discount ?? 0) +
        (appliedPrivateVoucher?.scope === "SHIPPING"
          ? appliedPrivateVoucher.discount
          : 0),
    );
    const shippingCost = Math.max(0, originalShippingCost - shippingDiscount);
    const discount = productDiscount;
    const totalBeforeRefund = Math.max(subtotal + shippingCost - discount, 0);

    // ── Saldo Refund validation ──
    // User bisa pakai saldo refund sebagai pengurang sisa bayar.
    // Constraints:
    //   - Hanya untuk logged-in user (effectiveUserId truthy)
    //   - Tidak boleh > wallet balance (avoid race via debit transaction)
    //   - Tidak boleh > totalBeforeRefund (max = bayar order penuh, sisa
    //     saldo tetap di wallet)
    // Pre-validation di sini agar response 400 cepat sebelum order create.
    // Final atomic debit di-handle di transaction.
    let refundBalanceUsed = 0;
    const requestedRefundBalance = Math.max(0, input.refundBalanceUsed ?? 0);
    if (requestedRefundBalance > 0) {
      if (!effectiveUserId) {
        return NextResponse.json(
          {
            message:
              "Saldo Refund hanya bisa dipakai oleh member login. Login dulu untuk pakai saldo.",
          },
          { status: 400 },
        );
      }
      const wallet = await getOrCreateWallet(effectiveUserId);
      if (wallet.status === "FROZEN") {
        return NextResponse.json(
          {
            message:
              "Saldo Refund kamu sedang di-freeze. Hubungi admin untuk info lebih lanjut.",
          },
          { status: 400 },
        );
      }
      if (requestedRefundBalance > wallet.availableBalance) {
        return NextResponse.json(
          {
            message: `Saldo Refund tidak cukup. Saldo kamu Rp${wallet.availableBalance.toLocaleString("id-ID")}.`,
          },
          { status: 400 },
        );
      }
      // Clamp ke total (saldo > total = sisa saldo tetap di wallet).
      refundBalanceUsed = Math.min(requestedRefundBalance, totalBeforeRefund);
    }

    const total = Math.max(totalBeforeRefund - refundBalanceUsed, 0);

    const appliedVouchers: AppliedVoucher[] = [
      appliedFreeShippingVoucher,
      appliedProductVoucher,
      appliedLoyaltyVoucher,
      appliedPrivateVoucher,
    ].filter(Boolean) as AppliedVoucher[];
    const orderNumber = createOrderNumber();
    const trackingToken = createTrackingToken();

    // Kode unik 3-digit untuk TT manual (memudahkan admin identifikasi pembayaran)
    // Hanya digenerate kalau pembayaran MANUAL
    const uniqueCode =
      input.paymentProvider === "MANUAL"
        ? Math.floor(100 + Math.random() * 900)
        : null;
    const earnedPoints = Math.floor(total / 20000);

    // withSerializationRetry: Serializable isolation di bawah bisa abort
    // dengan P2034 (40001) saat 2+ checkout konkuren menyentuh produk yang
    // sama (flash sale). Retry sampai 3x supaya user tidak dapat error 500
    // untuk konflik yang sebenarnya transient. StockConflictError (stok
    // benar-benar habis) BUKAN P2034 → propagate tanpa retry.
    const order = await withSerializationRetry(() =>
      prisma.$transaction(async (tx) => {
      // Track produk varian yang stoknya berubah → perlu re-sync Product.stock
      const variantProductIdsToSync = new Set<string>();

      for (const item of checkoutItems) {
        if (item.variantId) {
          // Atomic stock guard: validate stock >= requested qty and deduct while the row is locked by the write.
          const updateResult = await tx.productVariant.updateMany({
            where: { id: item.variantId, stock: { gte: item.quantity }, isActive: true, deletedAt: null },
            data: { stock: { decrement: item.quantity } },
          });
          if (updateResult.count !== 1) {
            const latest = await tx.productVariant.findFirst({
              where: { id: item.variantId },
              select: { stock: true, isActive: true, deletedAt: true },
            });
            const available = latest && latest.isActive && !latest.deletedAt ? latest.stock : 0;
            throw new StockConflictError(
              `${itemLabel(item)} hanya tersedia ${available} unit. Silakan cek keranjang lagi.`,
            );
          }
          variantProductIdsToSync.add(item.productId);
        } else {
          // Atomic stock guard for non-variant product rows.
          const updateResult = await tx.product.updateMany({
            where: { id: item.productId, stock: { gte: item.quantity }, isActive: true },
            data: { stock: { decrement: item.quantity } },
          });
          if (updateResult.count !== 1) {
            const latest = await tx.product.findFirst({
              where: { id: item.productId },
              select: { stock: true, isActive: true },
            });
            const available = latest && latest.isActive ? latest.stock : 0;
            throw new StockConflictError(
              `${item.name} hanya tersedia ${available} unit. Silakan cek keranjang lagi.`,
            );
          }
        }
      }

      // Re-sync Product.stock = SUM semua varian aktif (untuk produk yang variantnya berubah)
      for (const pid of variantProductIdsToSync) {
        const agg = await tx.productVariant.aggregate({
          where: { productId: pid, deletedAt: null, isActive: true },
          _sum: { stock: true },
        });
        await tx.product.update({
          where: { id: pid },
          data: { stock: agg._sum.stock ?? 0 },
        });
      }

      const createdOrder = await tx.order.create({
        data: {
          orderNumber,
          trackingToken,
          userId: effectiveUserId,
          customerName: input.customerName,
          customerPhone: input.customerPhone,
          customerEmail: input.customerEmail || null,
          shippingAddress: isSelfPickup ? SELF_PICKUP_STORE.address : input.shippingAddress,
          shippingCity: isSelfPickup ? "Medan Kota" : input.shippingCity,
          shippingPostalCode: isSelfPickup ? null : input.shippingPostalCode,
          shippingLatitude: isSelfPickup ? SELF_PICKUP_STORE.latitude : input.shippingLatitude ?? null,
          shippingLongitude: isSelfPickup ? SELF_PICKUP_STORE.longitude : input.shippingLongitude ?? null,
          shippingPinpointAddress: isSelfPickup ? null : input.shippingPinpointAddress || null,
          shippingAreaId: isSelfPickup ? SELF_PICKUP_METHOD : input.shippingAreaId,
          shippingAreaLabel: isSelfPickup ? SELF_PICKUP_STORE.name : input.shippingAreaLabel || null,
          shippingProvinceName: isSelfPickup ? null : input.shippingProvinceName || null,
          shippingDistrictName: isSelfPickup ? null : input.shippingDistrictName || null,
          orderType: isSelfPickup ? SELF_PICKUP_METHOD : "DELIVERY",
          shippingMethod: isSelfPickup ? SELF_PICKUP_METHOD : "DELIVERY",
          courierCode: isSelfPickup ? null : input.courierCode,
          courierService: isSelfPickup ? null : input.courierService,
          pickupStoreName: isSelfPickup ? SELF_PICKUP_STORE.name : null,
          pickupStoreAddress: isSelfPickup ? SELF_PICKUP_STORE.address : null,
          pickupStoreLatitude: isSelfPickup ? SELF_PICKUP_STORE.latitude : null,
          pickupStoreLongitude: isSelfPickup ? SELF_PICKUP_STORE.longitude : null,
          pickupHours: isSelfPickup ? SELF_PICKUP_STORE.hours : null,
          pickupStatus: isSelfPickup ? "WAITING_PAYMENT" : null,
          subtotal,
          shippingCost,
          discount,
          productDiscount,
          shippingDiscount,
          refundBalanceUsed,
          total,
          voucherCode:
            appliedProductVoucher?.code ??
            appliedLoyaltyVoucher?.code ??
            appliedFreeShippingVoucher?.code ??
            null,
          manualVoucherCode: appliedPrivateVoucher?.code ?? null,
          freeShippingVoucherCode: appliedFreeShippingVoucher?.code ?? null,
          productVoucherCode: appliedProductVoucher?.code ?? null,
          loyaltyVoucherCode: appliedLoyaltyVoucher?.code ?? null,
          privateVoucherCode: appliedPrivateVoucher?.code ?? null,
          manualBank: input.manualBank ?? null,
          uniqueCode,
          notes: input.notes,
          paymentProvider: input.paymentProvider,
          // Order full saldo refund (total = 0): auto-PAID + status
          // PROCESSING. Saldo refund = uang internal yang sudah debited
          // atomic di transaction — tidak perlu verify payment manual.
          // Skip "Belum Bayar" + "PAID intermediate" — langsung masuk
          // tab Diproses (match Shopee/Tokopedia pattern).
          //
          // Partial saldo (saldo > 0 tapi total > 0): tetap PENDING +
          // UNPAID/PENDING — user masih harus transfer sisa.
          paymentStatus: total === 0
              ? "PAID"
              : (input.paymentProvider === "MANUAL" ? "PENDING" : "UNPAID"),
          status: total === 0 ? "PROCESSING" : "PENDING",
          items: {
            create: checkoutItems.map((item) => ({
              productId: item.productId,
              variantId: item.variantId ?? null,
              variantLabel: item.variantLabel ?? null,
              name: item.name,
              price: item.price,
              quantity: item.quantity,
              weightGram: item.weightGram,
            })),
          },
        },
      });

      if (earnedPoints > 0) {
        await tx.customerPoint.create({
          data: {
            userId: effectiveUserId,
            points: earnedPoints,
            source: `ORDER:${orderNumber}`,
          },
        });
      }

      // Debit saldo refund kalau user pakai. Atomic inside transaction —
      // kalau wallet balance kurang (race condition antara pre-validation
      // dan transaction), debitWallet throw → transaction rollback,
      // order tidak ke-create. Helper handle ledger entry creation juga.
      if (refundBalanceUsed > 0 && effectiveUserId) {
        await debitWallet(
          {
            userId: effectiveUserId,
            amount: refundBalanceUsed,
            sourceOrderId: createdOrder.id,
            note: `Dipakai untuk pesanan ${orderNumber}`,
          },
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          tx as any,
        );
      }

      // Claim voucher atomically — guard against race jika maxUsage tercapai
      // setelah pre-validation di luar transaction. Loop semua voucher
      // (customer + manual) yang ter-apply.
      for (const v of appliedVouchers) {
        const claim = await tx.voucher.updateMany({
          where: {
            id: v.id,
            isActive: true,
            ...(v.maxUsage !== null ? { usedCount: { lt: v.maxUsage } } : {}),
          },
          data: { usedCount: { increment: 1 } },
        });
        if (claim.count !== 1) {
          throw new Error(
            `Voucher ${v.code} sudah mencapai batas pemakaian. Silakan coba lagi.`,
          );
        }
        // Per-user usage limit guard — ENFORCED DI DALAM txn Serializable,
        // mirror logika isVoucherUsageLimitReached (lib/voucher-helpers.ts).
        // Pre-check di luar txn (L365) bisa di-bypass race: 2 order
        // concurrent user sama dua-duanya lolos pre-check; updateMany di
        // atas cuma guard maxUsage GLOBAL, bukan per-user.
        //
        // KONVENSI (sama dengan check lama): usageLimitPerUser <= 0 ATAU
        // period NONE = TANPA BATAS per-user → skip. (Bug sebelumnya:
        // pakai `!== null` → treat 0/"Tanpa batas" sebagai "maks 0x" →
        // tolak voucher unlimited di pemakaian pertama. Lihat regresi
        // NATA-OKS.) Untuk limit > 0: count VoucherUsage (voucher, user)
        // DALAM window period (DAY/WEEK/MONTH/LIFETIME), throw kalau
        // sudah >= limit. Count BEFORE createMany di bawah.
        const perUserLimit = v.usageLimitPerUser ?? 1;
        const period = v.usageLimitPeriod ?? "LIFETIME";
        if (period !== "NONE" && perUserLimit > 0 && effectiveUserId) {
          const nowMs = Date.now();
          let cutoff: Date | null = null;
          if (period === "DAY") {
            cutoff = new Date(nowMs - 24 * 60 * 60 * 1000);
          } else if (period === "WEEK") {
            cutoff = new Date(nowMs - 7 * 24 * 60 * 60 * 1000);
          } else if (period === "MONTH") {
            cutoff = new Date(nowMs - 30 * 24 * 60 * 60 * 1000);
          }
          // LIFETIME → cutoff null → count semua usage.
          const usedByUser = await tx.voucherUsage.count({
            where: {
              voucherId: v.id,
              userId: effectiveUserId,
              ...(cutoff ? { usedAt: { gte: cutoff } } : {}),
            },
          });
          if (usedByUser >= perUserLimit) {
            throw new Error(
              `Voucher ${v.code} sudah mencapai batas pemakaian kamu. Silakan coba lagi.`,
            );
          }
        }
      }

      if (appliedVouchers.length > 0) {
        await tx.voucherUsage.createMany({
          data: appliedVouchers.map((v) => ({
            voucherId: v.id,
            userId: effectiveUserId,
            orderId: createdOrder.id,
            discountAmount: v.discount,
            voucherType: v.type,
          })),
          skipDuplicates: true,
        });
      }

      return createdOrder;
      }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable })
    );

    let paymentUrl: string | undefined;
    let paymentReference: string | undefined;

    if (input.paymentProvider === "MIDTRANS") {
      try {
        const payment = await createMidtransPayment(order);
        paymentUrl = payment.url;
        paymentReference = payment.reference;
      } catch (paymentErr) {
        // ── Payment gateway gagal — ROLLBACK semua state yang sudah commit ──
        // Restore stok, hapus order, decrement voucher.usedCount, hapus points
        try {
          await prisma.$transaction(async (tx) => {
            const variantProductIds = new Set<string>();
            for (const item of checkoutItems) {
              if (item.variantId) {
                await tx.productVariant.updateMany({
                  where: { id: item.variantId },
                  data: { stock: { increment: item.quantity } },
                });
                variantProductIds.add(item.productId);
              } else {
                await tx.product.updateMany({
                  where: { id: item.productId },
                  data: { stock: { increment: item.quantity } },
                });
              }
            }
            // Re-sync Product.stock untuk produk yang punya varian
            for (const pid of variantProductIds) {
              const agg = await tx.productVariant.aggregate({
                where: { productId: pid, deletedAt: null, isActive: true },
                _sum: { stock: true },
              });
              await tx.product.update({
                where: { id: pid },
                data: { stock: agg._sum.stock ?? 0 },
              });
            }
            for (const v of appliedVouchers) {
              await tx.voucher.update({
                where: { id: v.id },
                data: { usedCount: { decrement: 1 } },
              });
            }
            await tx.voucherUsage.deleteMany({
              where: { orderId: order.id },
            });
            await tx.customerPoint.deleteMany({
              where: { source: `ORDER:${orderNumber}` },
            });
            // Hapus order — cascade akan handle OrderItems
            await tx.order.delete({ where: { id: order.id } });
          });
        } catch (rollbackErr) {
          // Rollback gagal: order ada tapi tanpa paymentUrl, stok hilang.
          // Log untuk admin investigate manual. Jangan masking error pembayaran.
          console.error("[order rollback failed]", { orderNumber, rollbackErr });
        }
        console.error("[payment provider failed]", { orderNumber, paymentErr });
        return NextResponse.json(
          {
            message:
              "Pembayaran gagal dibuat. Silakan coba lagi atau pilih metode lain.",
          },
          { status: 502 }
        );
      }
    }

    if (paymentUrl || paymentReference) {
      // Trade-off: update ini DI LUAR order $transaction supaya call ke
      // Midtrans gateway tidak hold long-running transaction (Serializable
      // isolation × HTTP roundtrip = potential lock contention).
      // Konsekuensi: kalau Midtrans success TAPI update ini gagal (DB hiccup),
      // order tidak punya paymentUrl/paymentReference. Webhook tetap kerja
      // (route via order_id), tapi link "Bayar" di order detail customer
      // missing. Mitigation: customer bisa request resend via "Bayar Ulang"
      // di UI yang akan re-create payment session.
      // TODO: kalau ini sering terjadi, retry sekali atau log alert ke admin.
      await prisma.order.update({
        where: { id: order.id },
        data: { paymentUrl, paymentReference, paymentStatus: "PENDING" },
      });
    }

    // Notifikasi order via WhatsApp dihapus — customer dapat konfirmasi
    // lewat halaman success + email. Push notification akan dipakai untuk
    // status update berikutnya (PAID, SHIPPED, dst.) lewat sendOrderStatusPush
    // di route lain. WA Fonnte sekarang reserved khusus untuk OTP.

    // Push notif ke admin via after() — checkout response tetap cepat,
    // tapi eksekusi dijamin. Sebelumnya `void` promise yang bisa dibekukan
    // Vercel sebelum jalan → admin tidak dapat banner "Order baru!" dan
    // telat memproses pesanan.
    after(async () => {
      const { sendAdminOrderNewPush } = await import("@/lib/push-admin");
      await sendAdminOrderNewPush({
        orderNumber,
        customerName: input.customerName,
        total,
      });
    });

    return NextResponse.json({
      message: input.paymentProvider === "MANUAL"
        ? "Order dibuat. Silakan lanjutkan instruksi transfer manual."
        : "Order dibuat.",
      orderNumber,
      trackingToken: order.trackingToken,
      detailUrl: buildOrderDetailPath(order.orderNumber, order.trackingToken),
      earnedPoints,
      paymentUrl,
      snapToken: input.paymentProvider === "MIDTRANS" ? paymentReference : undefined,
    });
  } catch (error) {
    console.error(error);
    if (error instanceof StockConflictError) {
      return NextResponse.json({ message: error.message }, { status: error.status });
    }
    if (error instanceof VoucherValidationError) {
      return NextResponse.json({ message: error.message }, { status: error.status });
    }
    if (error instanceof InvalidCustomerSessionError) {
      return NextResponse.json({ message: error.message }, { status: 401 });
    }
    // Serialization failure (P2034) yang sudah exhaust retry di
    // withSerializationRetry — kontensi tinggi tak teratasi. Return 409
    // (bukan 500) dengan pesan retry-able supaya client bisa prompt user
    // coba lagi, bukan treat sebagai error fatal.
    if (isSerializationFailure(error)) {
      return NextResponse.json(
        { message: "Sistem sedang sibuk memproses banyak pesanan. Coba lagi sebentar." },
        { status: 409 },
      );
    }
    return NextResponse.json({ message: error instanceof Error ? error.message : "Gagal membuat order." }, { status: 500 });
  }
}
