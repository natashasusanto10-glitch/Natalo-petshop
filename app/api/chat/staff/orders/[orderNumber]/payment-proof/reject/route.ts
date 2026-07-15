import { NextRequest, NextResponse } from "next/server";
import { verifyPaymentStaffRequest } from "@/lib/chat/staff-auth";
import { prisma } from "@/lib/prisma";
import { PaymentConfirmationConflict } from "@/lib/order-payment-confirmation";

const NO_STORE = { "Cache-Control": "private, no-store" };

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> },
) {
  const auth = await verifyPaymentStaffRequest(request);
  if (auth instanceof NextResponse) return auth;
  const { orderNumber } = await params;
  if (!orderNumber || orderNumber.length > 80) {
    return NextResponse.json({ error: "Nomor order tidak valid" }, { status: 400, headers: NO_STORE });
  }
  const body = await request.json().catch(() => null) as {
    reason?: unknown;
    proofVersion?: unknown;
  } | null;
  const reason = typeof body?.reason === "string" ? body.reason.trim() : "";
  const expectedVersion = body?.proofVersion;
  if (!Number.isSafeInteger(expectedVersion) || (expectedVersion as number) < 1) {
    return NextResponse.json(
      { error: "proofVersion wajib berupa integer positif" },
      { status: 400, headers: NO_STORE },
    );
  }
  if (reason.length < 3 || reason.length > 500) {
    return NextResponse.json(
      { error: "Alasan penolakan wajib 3–500 karakter" },
      { status: 400, headers: NO_STORE },
    );
  }
  try {
    const result = await prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({
        where: { orderNumber },
        select: {
          id: true,
          paymentProofUrl: true,
          paymentProofVersion: true,
          paymentProofStatus: true,
        },
      });
      if (!order) return { kind: "missing" as const };
      if (!order.paymentProofUrl || order.paymentProofVersion < 1) return { kind: "no-proof" as const };
      if (
        order.paymentProofVersion !== expectedVersion ||
        order.paymentProofStatus !== "PENDING_REVIEW"
      ) return { kind: "conflict" as const };
      const reviewedAt = new Date();
      const updated = await tx.order.updateMany({
        where: {
          id: order.id,
          paymentProofVersion: expectedVersion as number,
          paymentProofStatus: "PENDING_REVIEW",
        },
        data: {
          paymentProofStatus: "REJECTED",
          paymentProofReviewedAt: reviewedAt,
          paymentProofReviewedBy: auth.uid,
          paymentProofRejectReason: reason,
        },
      });
      if (updated.count !== 1) return { kind: "conflict" as const };
      const proofUpdated = await tx.orderPaymentProof.updateMany({
        where: { orderId: order.id, version: expectedVersion as number, status: "PENDING_REVIEW" },
        data: {
          status: "REJECTED",
          reviewedAt,
          reviewedBy: auth.uid,
          rejectReason: reason,
        },
      });
      if (proofUpdated.count !== 1) {
        throw new PaymentConfirmationConflict("Riwayat bukti transfer tidak sinkron.");
      }
      return { kind: "ok" as const, version: expectedVersion as number };
    });
    if (result.kind === "missing") {
      return NextResponse.json({ error: "Order tidak ditemukan" }, { status: 404, headers: NO_STORE });
    }
    if (result.kind === "no-proof") {
      return NextResponse.json({ error: "Bukti transfer belum tersedia" }, { status: 409, headers: NO_STORE });
    }
    if (result.kind === "conflict") {
      return NextResponse.json(
        { error: "Bukti transfer baru saja berubah. Muat ulang lalu coba lagi." },
        { status: 409, headers: NO_STORE },
      );
    }
    console.info(JSON.stringify({
      event: "payment_proof_reviewed",
      action: "rejected",
      orderNumber,
      proofVersion: result.version,
      staffUid: auth.uid,
    }));
    return NextResponse.json({
      paymentProof: { status: "REJECTED", version: result.version, rejectReason: reason },
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
      action: "rejected",
      orderNumber,
      error: error instanceof Error ? error.message.slice(0, 250) : "unknown",
    }));
    return NextResponse.json({ error: "Gagal menolak bukti transfer" }, { status: 500, headers: NO_STORE });
  }
}
