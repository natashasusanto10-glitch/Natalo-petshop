import { NextRequest, NextResponse } from "next/server";
import { createHash } from "crypto";
import { prisma } from "@/lib/prisma";
import { createBiteshipShipmentIfReady } from "@/lib/biteship";
import { sendOrderStatusPush } from "@/lib/push";
import { SELF_PICKUP_METHOD } from "@/lib/self-pickup";
import { sendPaymentConfirmed } from "@/lib/whatsapp";

type MidtransNotification = {
  order_id: string;
  status_code: string;
  gross_amount: string;
  signature_key: string;
  transaction_status: string;
  fraud_status?: string;
  payment_type?: string;
};

function verifySignature(
  notification: MidtransNotification,
  serverKey: string
) {
  const raw = `${notification.order_id}${notification.status_code}${notification.gross_amount}${serverKey}`;
  const expected = createHash("sha512").update(raw).digest("hex");
  return expected === notification.signature_key;
}

function resolvePaymentStatus(transactionStatus: string, fraudStatus?: string) {
  if (transactionStatus === "capture") {
    return fraudStatus === "accept" ? "PAID" : "PENDING";
  }
  if (transactionStatus === "settlement") return "PAID";
  if (transactionStatus === "pending") return "PENDING";
  if (
    transactionStatus === "deny" ||
    transactionStatus === "cancel" ||
    transactionStatus === "expire"
  )
    return "FAILED";
  if (transactionStatus === "refund") return "REFUNDED";
  return "PENDING";
}

export async function POST(request: NextRequest) {
  const serverKey = process.env.MIDTRANS_SERVER_KEY;
  if (!serverKey) {
    return NextResponse.json(
      { message: "Server key tidak dikonfigurasi" },
      { status: 500 }
    );
  }

  const notification: MidtransNotification = await request.json();

  if (!verifySignature(notification, serverKey)) {
    return NextResponse.json(
      { message: "Signature tidak valid" },
      { status: 403 }
    );
  }

  const paymentStatus = resolvePaymentStatus(
    notification.transaction_status,
    notification.fraud_status
  );

  const order = await prisma.order.findUnique({
    where: { orderNumber: notification.order_id },
  });

  if (!order) {
    return NextResponse.json(
      { message: "Order tidak ditemukan" },
      { status: 404 }
    );
  }

  const updatedOrder = await prisma.order.update({
    where: { orderNumber: notification.order_id },
    data: {
      paymentStatus,
      status:
        paymentStatus === "PAID" &&
        order.status === "PENDING" &&
        order.orderType === SELF_PICKUP_METHOD
          ? "PROCESSING"
          : paymentStatus === "PAID" && order.status === "PENDING"
          ? "PAID"
          : paymentStatus === "REFUNDED"
          ? "REFUNDED"
          : undefined,
      pickupStatus:
        paymentStatus === "PAID" && order.orderType === SELF_PICKUP_METHOD
          ? "PREPARING"
          : undefined,
    },
  });

  if (paymentStatus === "PAID" && order.paymentStatus !== "PAID") {
    if (updatedOrder.orderType !== SELF_PICKUP_METHOD) {
      createBiteshipShipmentIfReady(updatedOrder.id).catch(() => {});
    }
    sendOrderStatusPush(
      updatedOrder.id,
      updatedOrder.orderNumber,
      "PAID"
    ).catch(() => {});
    sendPaymentConfirmed(updatedOrder).catch((error) => {
      console.error("[whatsapp] payment confirmed notification failed", error);
    });
  }

  if (paymentStatus === "REFUNDED" && order.paymentStatus !== "REFUNDED") {
    sendOrderStatusPush(
      updatedOrder.id,
      updatedOrder.orderNumber,
      "REFUNDED"
    ).catch(() => {});
  }

  return NextResponse.json({ message: "OK" });
}
