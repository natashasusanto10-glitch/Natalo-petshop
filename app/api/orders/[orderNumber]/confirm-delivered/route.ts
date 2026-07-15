/**
 * POST /api/orders/[orderNumber]/confirm-delivered
 *
 * User mengkonfirmasi paket sudah diterima (Shopee/Tokopedia "Pesanan
 * Diterima" pattern). Setelah konfirmasi:
 *   - order.status berubah SHIPPED → DELIVERED
 *   - Window refund / komplain TUTUP (lihat issueRefundToWallet guard
 *     untuk status DELIVERED di admin actions.ts)
 *   - Email + push notif "Pesanan selesai" terkirim ke customer
 *   - Customer biasanya di-prompt review produk di UI berikutnya
 *
 * Aturan:
 *   - Hanya order yang dia OWN (matching session userId)
 *   - Hanya status SHIPPED yang allowed
 *     (sebelum SHIPPED: paket belum dikirim, masih bisa cancel)
 *     (DELIVERED/CANCELLED/REFUNDED: terminal, tidak perlu confirm)
 *     (SELF_PICKUP flow: pakai admin markAsPickedUp, bukan endpoint ini)
 *
 * Idempotent: kalau order sudah DELIVERED, return 200 dengan flag
 * `alreadyConfirmed` instead of error — supaya client tidak menampilkan
 * pesan gagal kalau user double-tap tombolnya.
 *
 * Self-pickup: order pickup tidak transit SHIPPED — status berubah
 * PROCESSING → READY_FOR_PICKUP → DELIVERED via markAsPickedUp di admin
 * dashboard. User tidak perlu konfirmasi karena admin yang serahkan +
 * scan QR di toko.
 */

import { after, NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { assertSameOrigin } from "@/lib/csrf";
import { transitionOrderStatus } from "@/lib/order-transitions";
import { sendOrderStatusEmail } from "@/lib/email-order";
import { sendOrderStatusPush } from "@/lib/push";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> }
) {
  const csrfReject = assertSameOrigin(request);
  if (csrfReject) return csrfReject;

  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json(
      { error: "Silakan login member terlebih dahulu." },
      { status: 401 }
    );
  }

  const { orderNumber } = await params;
  if (!orderNumber || orderNumber.trim().length === 0) {
    return NextResponse.json(
      { error: "Order number tidak valid." },
      { status: 400 }
    );
  }

  const order = await prisma.order.findUnique({
    where: { orderNumber },
    select: {
      id: true,
      orderNumber: true,
      userId: true,
      status: true,
      orderType: true,
      customerName: true,
      customerEmail: true,
      customerPhone: true,
      trackingToken: true,
      trackingNumber: true,
      courierCode: true,
      courierService: true,
      total: true,
      paymentUrl: true,
    },
  });

  if (!order) {
    return NextResponse.json(
      { error: "Pesanan tidak ditemukan." },
      { status: 404 }
    );
  }

  // Ownership — user A tidak boleh konfirmasi order user B walau punya
  // nomor order-nya.
  if (order.userId !== session.sub) {
    return NextResponse.json(
      { error: "Pesanan ini bukan milikmu." },
      { status: 403 }
    );
  }

  // Idempotent — kalau sudah DELIVERED, return ok dengan flag supaya
  // client UI tidak salah show error message untuk double-tap.
  if (order.status === "DELIVERED") {
    return NextResponse.json({
      ok: true,
      alreadyConfirmed: true,
      orderNumber: order.orderNumber,
      status: "DELIVERED",
      message: "Pesanan sudah ditandai selesai sebelumnya.",
    });
  }

  if (order.status !== "SHIPPED") {
    const reasonByStatus: Record<string, string> = {
      PENDING: "Pesanan belum dibayar.",
      PAID: "Pesanan masih menunggu diproses penjual.",
      PROCESSING: "Pesanan masih dipacking, belum dikirim.",
      READY_FOR_PICKUP:
        "Pesanan self-pickup — konfirmasi penerimaan dilakukan saat ambil di toko.",
      CANCELLED: "Pesanan sudah dibatalkan.",
      REFUNDED: "Pesanan sudah di-refund.",
    };
    return NextResponse.json(
      {
        error:
          reasonByStatus[order.status] ??
          `Pesanan tidak bisa dikonfirmasi (status: ${order.status}).`,
      },
      { status: 409 }
    );
  }

  // Self-pickup safety (defensive — secara matrix transition self-pickup
  // tidak transit SHIPPED, tapi guard kalau ada edge case data).
  if (order.orderType === "SELF_PICKUP") {
    return NextResponse.json(
      {
        error:
          "Pesanan self-pickup tidak butuh konfirmasi via app. Datang ke toko untuk ambil.",
      },
      { status: 409 }
    );
  }

  try {
    await transitionOrderStatus(order.id, "DELIVERED", {}, {
      actorType: "CUSTOMER",
      actorId: session.sub,
      idempotencyKey: `customer-confirm-delivered:${order.id}`,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Gagal update status.";
    return NextResponse.json({ error: message }, { status: 409 });
  }

  // Email + push notif via after() — response tetap cepat, error dari
  // mailer tidak block client, TAPI eksekusi dijamin. Sebelumnya `void`
  // promise yang bisa dibekukan Vercel sebelum jalan → email/push
  // DELIVERED tidak pernah terkirim.
  const emailCtx = {
    orderNumber: order.orderNumber,
    trackingToken: order.trackingToken,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    customerEmail: order.customerEmail,
    total: order.total,
    trackingNumber: order.trackingNumber,
    courierCode: order.courierCode,
    courierService: order.courierService,
    paymentUrl: order.paymentUrl,
  };
  after(() => sendOrderStatusEmail("DELIVERED", emailCtx).catch(() => {}));
  after(() =>
    sendOrderStatusPush(order.id, order.orderNumber, "DELIVERED").catch(
      () => {},
    ),
  );

  return NextResponse.json({
    ok: true,
    alreadyConfirmed: false,
    orderNumber: order.orderNumber,
    status: "DELIVERED",
    message: "Pesanan ditandai selesai. Terima kasih telah berbelanja!",
  });
}
