import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { sendPaymentConfirmed } from "@/lib/whatsapp";

type XenditInvoiceNotification = {
  external_id?: string;
  status?: string;
  id?: string;
};

function resolvePaymentStatus(status?: string) {
  if (status === "PAID" || status === "SETTLED") return "PAID";
  if (status === "EXPIRED") return "EXPIRED";
  if (status === "FAILED") return "FAILED";
  return "PENDING";
}

export async function POST(request: NextRequest) {
  const callbackToken = process.env.XENDIT_CALLBACK_TOKEN;
  if (callbackToken) {
    const receivedToken = request.headers.get("x-callback-token");
    if (receivedToken !== callbackToken) {
      return NextResponse.json({ message: "Callback token tidak valid" }, { status: 403 });
    }
  }

  const notification: XenditInvoiceNotification = await request.json();
  const orderNumber = notification.external_id;

  if (!orderNumber) {
    return NextResponse.json({ message: "external_id tidak ditemukan" }, { status: 400 });
  }

  const paymentStatus = resolvePaymentStatus(notification.status);
  const order = await prisma.order.findUnique({
    where: { orderNumber },
  });

  if (!order) {
    return NextResponse.json({ message: "Order tidak ditemukan" }, { status: 404 });
  }

  const updatedOrder = await prisma.order.update({
    where: { orderNumber },
    data: {
      paymentStatus,
      paymentReference: notification.id || order.paymentReference,
      status: paymentStatus === "PAID" && order.status === "PENDING" ? "PAID" : undefined,
    },
  });

  if (paymentStatus === "PAID" && order.paymentStatus !== "PAID") {
    sendPaymentConfirmed(updatedOrder).catch((error) => {
      console.error("[whatsapp] payment confirmed notification failed", error);
    });
  }

  return NextResponse.json({ message: "OK" });
}
