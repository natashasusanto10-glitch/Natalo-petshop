import { NextRequest, NextResponse } from "next/server";
import { verifyPaymentStaffRequest } from "@/lib/chat/staff-auth";
import { prisma } from "@/lib/prisma";
import {
  confirmOrderPayment,
  PaymentConfirmationConflict,
} from "@/lib/order-payment-confirmation";
import { runWithStaffCors, staffCorsPreflight } from "@/lib/chat/staff-cors";

const NO_STORE = { "Cache-Control": "private, no-store" };

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> },
) {
  return runWithStaffCors(request, () => verifyPaymentProof(request, params));
}

export function OPTIONS(request: NextRequest) {
  return staffCorsPreflight(request);
}

async function verifyPaymentProof(
  request: NextRequest,
  params: Promise<{ orderNumber: string }>,
) {
  const auth = await verifyPaymentStaffRequest(request);
  if (auth instanceof NextResponse) return auth;
  const { orderNumber } = await params;
  if (!orderNumber || orderNumber.length > 80) {
    return NextResponse.json({ error: "Nomor order tidak valid" }, { status: 400, headers: NO_STORE });
  }
  const body = await request.json().catch(() => null) as { proofVersion?: unknown } | null;
  const expectedVersion = body?.proofVersion;
  if (!Number.isSafeInteger(expectedVersion) || (expectedVersion as number) < 1) {
    return NextResponse.json(
      { error: "proofVersion wajib berupa integer positif" },
      { status: 400, headers: NO_STORE },
    );
  }
  try {
    const order = await prisma.order.findUnique({
      where: { orderNumber },
      select: { id: true },
    });
    if (!order) {
      return NextResponse.json({ error: "Order tidak ditemukan" }, { status: 404, headers: NO_STORE });
    }
    await confirmOrderPayment({
      orderId: order.id,
      actorId: auth.uid,
      expectedProofVersion: expectedVersion as number,
      allowAlreadyPaid: true,
    });
    console.info(JSON.stringify({
      event: "payment_proof_reviewed",
      action: "verified",
      orderNumber,
      proofVersion: expectedVersion,
      staffUid: auth.uid,
    }));
    return NextResponse.json({
      paymentStatus: "PAID",
      paymentProof: { status: "VERIFIED", version: expectedVersion },
    }, { headers: NO_STORE });
  } catch (error) {
    if (error instanceof PaymentConfirmationConflict) {
      return NextResponse.json(
        { error: "Order atau bukti transfer sudah berubah. Muat ulang lalu coba lagi." },
        { status: 409, headers: NO_STORE },
      );
    }
    console.error(JSON.stringify({
      event: "payment_proof_review_failed",
      action: "verified",
      orderNumber,
      error: error instanceof Error ? error.message.slice(0, 250) : "unknown",
    }));
    return NextResponse.json({ error: "Gagal memverifikasi bukti transfer" }, { status: 500, headers: NO_STORE });
  }
}
