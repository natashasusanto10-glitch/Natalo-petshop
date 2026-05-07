import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { createOrderNumber } from "@/lib/format";
import { createOrderSchema } from "@/lib/validation";
import { sendAdminOrderCreated, sendOrderCreated } from "@/lib/whatsapp";

type CheckedOutItem = {
  productId: string;
  variantId?: string | null;
  variantLabel?: string | null;
  name: string;
  price: number;
  quantity: number;
  weightGram: number;
};

function withTimeout<T>(promise: Promise<T>, timeoutMs: number, label: string) {
  return Promise.race([
    promise,
    new Promise<T>((resolve) => {
      setTimeout(() => {
        resolve({
          ok: false,
          skipped: true,
          reason: `${label} timeout`,
        } as T);
      }, timeoutMs);
    }),
  ]);
}

async function createMidtransPayment(order: { orderNumber: string; total: number; customerName: string; customerEmail?: string | null; customerPhone: string }) {
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
        finish: `${process.env.NEXT_PUBLIC_SITE_URL}/order-status?order=${order.orderNumber}`,
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

async function createXenditPayment(order: { orderNumber: string; total: number; customerName: string; customerEmail?: string | null }) {
  const secretKey = process.env.XENDIT_SECRET_KEY;
  if (!secretKey) throw new Error("XENDIT_SECRET_KEY belum diisi.");

  const auth = Buffer.from(`${secretKey}:`).toString("base64");
  const res = await fetch("https://api.xendit.co/v2/invoices", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Basic ${auth}`,
    },
    body: JSON.stringify({
      external_id: order.orderNumber,
      amount: order.total,
      description: `Pembayaran order ${order.orderNumber}`,
      payer_email: order.customerEmail || undefined,
      success_redirect_url: `${process.env.NEXT_PUBLIC_SITE_URL}/order-status?order=${order.orderNumber}`,
      failure_redirect_url: `${process.env.NEXT_PUBLIC_SITE_URL}/checkout`,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Xendit error: ${text}`);
  }

  const data = await res.json();
  return { reference: data.id as string, url: data.invoice_url as string };
}

export async function POST(request: Request) {
  const json = await request.json();
  const parsed = createOrderSchema.safeParse(json);

  if (!parsed.success) {
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
      select: { id: true, name: true, price: true, discountPrice: true, stock: true, weightGram: true, isActive: true, hasVariants: true },
    }),
    variantIds.length
      ? prisma.productVariant.findMany({
          where: { id: { in: variantIds }, deletedAt: null, isActive: true },
          select: { id: true, productId: true, price: true, stock: true, weightGram: true },
        })
      : Promise.resolve([]),
  ]);

  const checkoutItems: CheckedOutItem[] = [];
  const stockErrors: string[] = [];

  for (const [, requested] of requestedMap) {
    const product = products.find((p) => p.id === requested.productId);
    if (!product || !product.isActive) {
      stockErrors.push("Produk di keranjang sudah tidak tersedia.");
      continue;
    }

    if (requested.variantId) {
      // ── Produk dengan varian ────────────────────────────────
      const variant = variants.find((v) => v.id === requested.variantId);
      if (!variant) {
        stockErrors.push(`Varian produk "${product.name}" sudah tidak tersedia.`);
        continue;
      }
      if (variant.stock < requested.quantity) {
        stockErrors.push(`"${product.name} (${requested.variantLabel ?? ""})" hanya tersedia ${variant.stock} unit.`);
        continue;
      }
      checkoutItems.push({
        productId: product.id,
        variantId: variant.id,
        variantLabel: requested.variantLabel,
        name: product.name,
        price: variant.price,
        quantity: requested.quantity,
        weightGram: variant.weightGram,
      });
    } else {
      // ── Produk tanpa varian ─────────────────────────────────
      if (product.stock < requested.quantity) {
        stockErrors.push(`${product.name} hanya tersedia ${product.stock}, sedangkan keranjang berisi ${requested.quantity}.`);
        continue;
      }
      checkoutItems.push({
        productId: product.id,
        variantId: null,
        variantLabel: null,
        name: product.name,
        price: product.discountPrice !== null && product.discountPrice < product.price
          ? product.discountPrice
          : product.price,
        quantity: requested.quantity,
        weightGram: product.weightGram,
      });
    }
  }

  if (stockErrors.length > 0) {
    return NextResponse.json({ message: stockErrors.join(" ") }, { status: 409 });
  }

  const subtotal = checkoutItems.reduce((sum, item) => sum + item.price * item.quantity, 0);
  let discount = 0;

  try {
    let appliedVoucherId: string | null = null;

    if (input.voucherCode) {
      const now = new Date();
      const voucher = await prisma.voucher.findUnique({
        where: { code: input.voucherCode.trim().toUpperCase() },
      });
      const isValid =
        voucher?.isActive &&
        subtotal >= voucher.minimumOrder &&
        (!voucher.expiresAt || voucher.expiresAt > now) &&
        voucher.startsAt <= now &&
        (voucher.maxUsage === null || voucher.usedCount < voucher.maxUsage);

      if (isValid && voucher) {
        if (voucher.discountPercent) discount += Math.floor((subtotal * voucher.discountPercent) / 100);
        if (voucher.discountAmount) discount += voucher.discountAmount;
        discount = Math.min(discount, subtotal);
        appliedVoucherId = voucher.id;
      }
    }

    const total = Math.max(subtotal + input.shippingCost - discount, 0);
    const orderNumber = createOrderNumber();

    // Kode unik 3-digit untuk TT manual (memudahkan admin identifikasi pembayaran)
    // Hanya digenerate kalau pembayaran MANUAL
    const uniqueCode =
      input.paymentProvider === "MANUAL"
        ? Math.floor(100 + Math.random() * 900)
        : null;
    const earnedPoints = Math.floor(total / 20000);

    let user = await prisma.user.findFirst({
      where: {
        OR: [
          { phone: input.customerPhone },
          input.customerEmail ? { email: input.customerEmail } : undefined,
        ].filter(Boolean) as { phone?: string; email?: string }[],
      },
    });

    if (!user) {
      user = await prisma.user.create({
        data: {
          name: input.customerName,
          phone: input.customerPhone,
          email: input.customerEmail || null,
        },
      });
    }

    const order = await prisma.$transaction(async (tx) => {
      // Track produk varian yang stoknya berubah → perlu re-sync Product.stock
      const variantProductIdsToSync = new Set<string>();

      for (const item of checkoutItems) {
        if (item.variantId) {
          // Deduct dari stok variant
          const updateResult = await tx.productVariant.updateMany({
            where: { id: item.variantId, stock: { gte: item.quantity }, isActive: true, deletedAt: null },
            data: { stock: { decrement: item.quantity } },
          });
          if (updateResult.count !== 1) {
            throw new Error(`${item.name} (${item.variantLabel ?? ""}) stoknya baru saja berubah. Silakan cek keranjang lagi.`);
          }
          variantProductIdsToSync.add(item.productId);
        } else {
          // Deduct dari stok produk (non-variant)
          const updateResult = await tx.product.updateMany({
            where: { id: item.productId, stock: { gte: item.quantity }, isActive: true },
            data: { stock: { decrement: item.quantity } },
          });
          if (updateResult.count !== 1) {
            throw new Error(`${item.name} stoknya baru saja berubah. Silakan cek keranjang lagi.`);
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
          userId: user.id,
          customerName: input.customerName,
          customerPhone: input.customerPhone,
          customerEmail: input.customerEmail || null,
          shippingAddress: input.shippingAddress,
          shippingCity: input.shippingCity,
          shippingPostalCode: input.shippingPostalCode,
          courierCode: input.courierCode,
          courierService: input.courierService,
          subtotal,
          shippingCost: input.shippingCost,
          discount,
          total,
          voucherCode: input.voucherCode,
          manualBank: input.manualBank ?? null,
          uniqueCode,
          notes: input.notes,
          paymentProvider: input.paymentProvider,
          paymentStatus: input.paymentProvider === "MANUAL" ? "PENDING" : "UNPAID",
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
            userId: user.id,
            points: earnedPoints,
            source: `ORDER:${orderNumber}`,
          },
        });
      }

      // Increment usedCount voucher
      if (appliedVoucherId) {
        await tx.voucher.update({
          where: { id: appliedVoucherId },
          data: { usedCount: { increment: 1 } },
        });
      }

      return createdOrder;
    });

    let paymentUrl: string | undefined;
    let paymentReference: string | undefined;

    if (input.paymentProvider === "MIDTRANS" || input.paymentProvider === "XENDIT") {
      try {
        const payment =
          input.paymentProvider === "MIDTRANS"
            ? await createMidtransPayment(order)
            : await createXenditPayment(order);
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
            if (appliedVoucherId) {
              await tx.voucher.update({
                where: { id: appliedVoucherId },
                data: { usedCount: { decrement: 1 } },
              });
            }
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
      await prisma.order.update({
        where: { id: order.id },
        data: { paymentUrl, paymentReference, paymentStatus: "PENDING" },
      });
    }

    const orderNotification = {
      ...order,
      paymentUrl,
      paymentReference,
      items: checkoutItems,
    };

    const waResults = await Promise.allSettled([
      withTimeout(sendOrderCreated(orderNotification), 8000, "customer order notification"),
      withTimeout(sendAdminOrderCreated(orderNotification), 8000, "admin order notification"),
    ]);

    waResults.forEach((result) => {
      if (result.status === "rejected") {
        console.error("[whatsapp] order notification failed", result.reason);
        return;
      }
      if (!result.value?.ok) {
        console.error("[whatsapp] order notification not sent", result.value);
      }
    });

    return NextResponse.json({
      message: input.paymentProvider === "MANUAL"
        ? "Order dibuat. Silakan lanjutkan instruksi transfer manual."
        : "Order dibuat.",
      orderNumber,
      earnedPoints,
      paymentUrl,
      snapToken: input.paymentProvider === "MIDTRANS" ? paymentReference : undefined,
    });
  } catch (error) {
    console.error(error);
    return NextResponse.json({ message: error instanceof Error ? error.message : "Gagal membuat order." }, { status: 500 });
  }
}
