import { NextRequest, NextResponse } from "next/server";
import { verifyStaffRequest } from "@/lib/chat/staff-auth";
import { prisma } from "@/lib/prisma";
import {
  hasValidPaymentProofBytes,
  normalizeAllowedPaymentProofType,
  parseAllowedPaymentProofUrl,
} from "@/lib/chat/payment-proof-security";
import { runWithStaffCors, staffCorsPreflight } from "@/lib/chat/staff-cors";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> },
) {
  return runWithStaffCors(request, () => getPaymentProof(request, params));
}

export function OPTIONS(request: NextRequest) {
  return staffCorsPreflight(request);
}

async function getPaymentProof(
  request: NextRequest,
  params: Promise<{ orderNumber: string }>,
) {
  const auth = await verifyStaffRequest(request);
  if (auth instanceof NextResponse) return auth;
  const { orderNumber } = await params;
  if (!orderNumber || orderNumber.length > 80) {
    return NextResponse.json({ error: "Nomor order tidak valid" }, { status: 400 });
  }
  const order = await prisma.order.findUnique({
    where: { orderNumber },
    select: { paymentProofUrl: true, paymentProofVersion: true },
  });
  if (!order?.paymentProofUrl) {
    return NextResponse.json({ error: "Bukti transfer belum tersedia" }, { status: 404 });
  }
  const proofUrl = parseAllowedPaymentProofUrl(order.paymentProofUrl);
  if (!proofUrl) {
    console.error(JSON.stringify({ event: "payment_proof_invalid_storage_url", orderNumber }));
    return NextResponse.json({ error: "Bukti transfer tidak dapat dibuka" }, { status: 502 });
  }
  try {
    const upstream = await fetch(proofUrl, { cache: "no-store", redirect: "error" });
    const contentType = upstream.headers.get("content-type") ?? "";
    const normalizedContentType = normalizeAllowedPaymentProofType(contentType);
    if (!upstream.ok || !normalizedContentType) {
      throw new Error("invalid proof response");
    }
    const bytes = new Uint8Array(await upstream.arrayBuffer());
    if (bytes.byteLength > 5 * 1024 * 1024) throw new Error("proof too large");
    if (!hasValidPaymentProofBytes(bytes, normalizedContentType)) {
      throw new Error("proof content mismatch");
    }
    console.info(JSON.stringify({
      event: "payment_proof_opened",
      orderNumber,
      proofVersion: order.paymentProofVersion,
      staffUid: auth.uid,
    }));
    return new NextResponse(bytes, {
      headers: {
        "Content-Type": normalizedContentType,
        "Content-Length": String(bytes.byteLength),
        "Cache-Control": "private, no-store",
        "Content-Security-Policy": "default-src 'none'; sandbox",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch (error) {
    console.error(JSON.stringify({
      event: "payment_proof_proxy_failed",
      orderNumber,
      error: error instanceof Error ? error.message.slice(0, 200) : "unknown",
    }));
    return NextResponse.json({ error: "Bukti transfer tidak dapat dibuka" }, { status: 502 });
  }
}
