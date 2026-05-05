import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { createOrderNumber } from "@/lib/format";
import { createOrderSchema } from "@/lib/validation";

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
  const subtotal = input.items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  let discount = 0;

  try {
    if (input.voucherCode) {
      const voucher = await prisma.voucher.findUnique({ where: { code: input.voucherCode } });
      if (voucher?.isActive && subtotal >= voucher.minimumOrder) {
        if (voucher.discountPercent) discount += Math.floor(subtotal * voucher.discountPercent / 100);
        if (voucher.discountAmount) discount += voucher.discountAmount;
      }
    }

    const total = Math.max(subtotal + input.shippingCost - discount, 0);
    const orderNumber = createOrderNumber();

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

    const order = await prisma.order.create({
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
        notes: input.notes,
        paymentProvider: input.paymentProvider,
        paymentStatus: input.paymentProvider === "MANUAL" ? "PENDING" : "UNPAID",
        items: {
          create: input.items.map((item) => ({
            productId: item.productId,
            name: item.name,
            price: item.price,
            quantity: item.quantity,
            weightGram: item.weightGram,
          })),
        },
      },
    });

    let paymentUrl: string | undefined;
    let paymentReference: string | undefined;

    if (input.paymentProvider === "MIDTRANS") {
      const payment = await createMidtransPayment(order);
      paymentUrl = payment.url;
      paymentReference = payment.reference;
    }

    if (input.paymentProvider === "XENDIT") {
      const payment = await createXenditPayment(order);
      paymentUrl = payment.url;
      paymentReference = payment.reference;
    }

    if (paymentUrl || paymentReference) {
      await prisma.order.update({
        where: { id: order.id },
        data: { paymentUrl, paymentReference, paymentStatus: "PENDING" },
      });
    }

    return NextResponse.json({
      message: input.paymentProvider === "MANUAL"
        ? "Order dibuat. Silakan lanjutkan instruksi transfer manual."
        : "Order dibuat.",
      orderNumber,
      paymentUrl,
      snapToken: input.paymentProvider === "MIDTRANS" ? paymentReference : undefined,
    });
  } catch (error) {
    console.error(error);
    return NextResponse.json({ message: error instanceof Error ? error.message : "Gagal membuat order." }, { status: 500 });
  }
}
