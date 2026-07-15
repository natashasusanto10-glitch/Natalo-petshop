import { after, NextRequest, NextResponse } from "next/server";
import { createHash } from "crypto";
import { prisma } from "@/lib/prisma";
import { createBiteshipShipmentIfReady } from "@/lib/biteship";
import { sendOrderStatusPush } from "@/lib/push";
import { SELF_PICKUP_METHOD } from "@/lib/self-pickup";
import { recordOrderStatusEvent } from "@/lib/order-transitions";
// Notifikasi payment confirmed via WhatsApp dihapus — customer dapat
// konfirmasi via email + push (sendOrderStatusPush) saja. Fonnte sekarang
// hanya untuk OTP register & login.

// Booking Biteship + push status dijadwalkan via after() — tetap dihitung
// ke durasi invocation, beri ruang di atas ack webhook yang cepat.
export const maxDuration = 30;

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

  // Amount integrity gate — verify gross_amount callback == order.total
  // SEBELUM mark PAID. Signature sudah verified, tapi signature dihitung
  // DARI gross_amount notif itu sendiri, jadi tidak menjamin amount ==
  // yang seharusnya dibayar. Tanpa cek ini, kalau ada Snap transaction
  // dengan amount mismatch (partial settlement, edited tx, dll), order
  // bisa flip PAID tanpa bayar penuh. gross_amount Midtrans string
  // desimal ("150000.00") → round ke int rupiah untuk compare.
  if (paymentStatus === "PAID") {
    const paidAmount = Math.round(Number(notification.gross_amount));
    if (!Number.isFinite(paidAmount) || paidAmount !== order.total) {
      console.warn(
        `[midtrans] amount mismatch order=${notification.order_id} ` +
          `paid=${notification.gross_amount} expected=${order.total} — ` +
          `NOT marking PAID`,
      );
      return NextResponse.json(
        { message: "Jumlah pembayaran tidak sesuai." },
        { status: 409 },
      );
    }
  }

  const updatedOrder = await prisma.$transaction(async (tx) => {
    const updated = await tx.order.update({
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
    if (paymentStatus === "PAID") {
      await recordOrderStatusEvent(tx, order.id, "PAID", {
        actorType: "PAYMENT_PROVIDER",
        actorId: "MIDTRANS",
        idempotencyKey: `midtrans:${order.id}:paid`,
        metadata: { transactionStatus: notification.transaction_status },
      });
      if (order.status === "PENDING" && order.orderType === SELF_PICKUP_METHOD) {
        await recordOrderStatusEvent(tx, order.id, "PROCESSING", {
          actorType: "PAYMENT_PROVIDER",
          actorId: "MIDTRANS",
          idempotencyKey: `midtrans:${order.id}:processing-after-paid`,
        });
      }
    } else if (paymentStatus === "REFUNDED") {
      await recordOrderStatusEvent(tx, order.id, "REFUNDED", {
        actorType: "PAYMENT_PROVIDER",
        actorId: "MIDTRANS",
        idempotencyKey: `midtrans:${order.id}:refunded`,
      });
    }
    return updated;
  });

  // Booking Biteship + push status via after() — ack webhook ke Midtrans
  // tetap cepat, TAPI eksekusi dijamin setelah response. Sebelumnya
  // fire-and-forget promise yang bisa dibekukan Vercel sebelum jalan →
  // shipment TIDAK PERNAH dibooking + user tidak dapat push PAID padahal
  // sudah bayar (kelas bug yang sama dengan feed publish-push).
  if (paymentStatus === "PAID" && order.paymentStatus !== "PAID") {
    if (updatedOrder.orderType !== SELF_PICKUP_METHOD) {
      after(() => createBiteshipShipmentIfReady(updatedOrder.id));
    }
    after(() =>
      sendOrderStatusPush(
        updatedOrder.id,
        updatedOrder.orderNumber,
        "PAID"
      ).catch(() => {})
    );
  }

  if (paymentStatus === "REFUNDED" && order.paymentStatus !== "REFUNDED") {
    after(() =>
      sendOrderStatusPush(
        updatedOrder.id,
        updatedOrder.orderNumber,
        "REFUNDED"
      ).catch(() => {})
    );
  }

  // Pembayaran kadaluarsa/gagal (deny/cancel/expire dari Midtrans) →
  // kabari user supaya tahu order hangus + bisa pesan ulang. Sebelumnya
  // tidak ada push untuk FAILED — user nunggu bayar VA, kadaluarsa,
  // tidak dikasih tahu → bingung "kok order hilang". Guard transition
  // supaya tidak re-push kalau webhook FAILED datang berkali-kali.
  if (paymentStatus === "FAILED" && order.paymentStatus !== "FAILED") {
    after(() =>
      sendOrderStatusPush(
        updatedOrder.id,
        updatedOrder.orderNumber,
        "FAILED"
      ).catch(() => {})
    );
  }

  return NextResponse.json({ message: "OK" });
}
