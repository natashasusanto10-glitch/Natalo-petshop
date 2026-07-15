import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { uploadToUT } from "@/lib/uploadthing";
import { getSession } from "@/lib/auth";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";
import { buildOrderContextV1 } from "@/lib/chat/order-contract";
import {
  ORDER_CONTEXT_OUTBOX_TYPE,
  orderContextOutboxKey,
  processOrderContextOutboxEvent,
} from "@/lib/chat/order-outbox";

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_SIZE = 5 * 1024 * 1024;

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ orderNumber: string }> },
) {
  const { orderNumber } = await params;

  if (!orderNumber || orderNumber.length > 80) {
    return NextResponse.json({ error: "Nomor order tidak valid" }, { status: 400 });
  }

  const order = await prisma.order
    .findUnique({
      where: { orderNumber },
      select: {
        id: true,
        orderNumber: true,
        userId: true,
        trackingToken: true,
        paymentProofUrl: true,
        paymentProofVersion: true,
        paymentProofStatus: true,
        paymentStatus: true,
      },
    })
    .catch(() => null);
  if (!order) {
    return NextResponse.json({ error: "Order tidak ditemukan" }, { status: 404 });
  }

  // ── Authorization — pattern sama dgn GET /pesanan/[orderNumber] di
  //   app/pesanan/[orderNumber]/page.tsx. User boleh upload bukti
  //   pembayaran HANYA kalau:
  //   1. Logged-in member yang own order (session.sub === order.userId), ATAU
  //   2. Akses via tracking link valid (?token=<order.trackingToken>) — untuk
  //      guest order yang tidak login.
  //
  //   Sebelumnya endpoint ini OPEN — siapapun bisa overwrite paymentProofUrl
  //   order user lain + spam upload 5MB ke UploadThing (cost + IDOR).
  const token = new URL(request.url).searchParams.get("token");
  const session = await getSession("CUSTOMER").catch(() => null);
  const isOwner = Boolean(session?.sub && order.userId === session.sub);
  const hasValidToken = Boolean(
    token && order.trackingToken && token === order.trackingToken,
  );
  if (!isOwner && !hasValidToken) {
    return NextResponse.json(
      { error: "Tidak punya akses ke order ini" },
      { status: 403 },
    );
  }
  if (order.paymentProofStatus === "VERIFIED" || order.paymentStatus === "PAID") {
    return NextResponse.json(
      { error: "Pembayaran sudah diverifikasi dan bukti tidak dapat diganti" },
      { status: 409 },
    );
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;

  if (!file) return NextResponse.json({ error: "File wajib diunggah" }, { status: 400 });
  if (!ALLOWED_TYPES.has(file.type)) {
    return NextResponse.json({ error: "Format harus JPG, PNG, atau WEBP" }, { status: 400 });
  }
  if (file.size > MAX_SIZE) {
    return NextResponse.json({ error: "Ukuran file maksimal 5 MB" }, { status: 400 });
  }

  // Magic-byte check — cegah polyglot/SVG-XSS payload dgn Content-Type
  // spoofed sebagai image/jpeg. Admin akan view proof di /admin/pickup-validation;
  // tanpa check ini, attacker bisa inject script via UploadThing trusted origin.
  const buffer = Buffer.from(await file.arrayBuffer());
  if (!validateImageMagicBytes(buffer, file.type)) {
    return NextResponse.json(
      { error: "Isi file tidak cocok dengan format gambar" },
      { status: 415 },
    );
  }

  try {
    const { url } = await uploadToUT(file, `proof-${orderNumber}`);
    const now = new Date();
    const saved = await prisma.$transaction(async (tx) => {
      const updated = await tx.order.update({
        where: { id: order.id },
        data: {
          paymentProofUrl: url,
          paymentProofUploadedAt: now,
          paymentProofVersion: { increment: 1 },
          paymentProofStatus: "PENDING_REVIEW",
          paymentProofReviewedAt: null,
          paymentProofReviewedBy: null,
          paymentProofRejectReason: null,
        },
        select: {
          id: true,
          userId: true,
          orderNumber: true,
          status: true,
          paymentStatus: true,
          paymentProofStatus: true,
          paymentProofUrl: true,
          paymentProofVersion: true,
          total: true,
          createdAt: true,
          _count: { select: { items: true } },
        },
      });
      await tx.orderPaymentProof.updateMany({
        where: { orderId: order.id, version: { lt: updated.paymentProofVersion } },
        data: { status: "REPLACED" },
      });
      await tx.orderPaymentProof.create({
        data: {
          orderId: updated.id,
          version: updated.paymentProofVersion,
          url,
          status: "PENDING_REVIEW",
          uploadedAt: now,
        },
      });

      let outboxEventId: string | null = null;
      if (updated.userId) {
        const context = buildOrderContextV1({
          ...updated,
          itemCount: updated._count.items,
        });
        const event = await tx.chatOutboxEvent.upsert({
          where: { eventKey: orderContextOutboxKey(updated.id) },
          create: {
            eventKey: orderContextOutboxKey(updated.id),
            type: ORDER_CONTEXT_OUTBOX_TYPE,
            aggregateId: updated.id,
            payload: { ...context, orderId: updated.id, customerId: updated.userId },
          },
          update: {
            type: ORDER_CONTEXT_OUTBOX_TYPE,
            payload: { ...context, orderId: updated.id, customerId: updated.userId },
            generation: { increment: 1 },
            status: "PENDING",
            attempts: 0,
            availableAt: now,
            lockedAt: null,
            processedAt: null,
            lastError: null,
          },
          select: { id: true },
        });
        outboxEventId = event.id;
      }
      return { updated, outboxEventId };
    });

    console.info(JSON.stringify({
      event: "payment_proof_uploaded",
      orderNumber,
      proofVersion: saved.updated.paymentProofVersion,
      outboxEventId: saved.outboxEventId,
    }));
    if (saved.outboxEventId) {
      // Delivery failure is persisted by the outbox processor and retried by
      // cron; it must never turn a successful proof upload into an HTTP 500.
      await processOrderContextOutboxEvent(saved.outboxEventId).catch(() => false);
    }
    return NextResponse.json({
      url,
      paymentProofStatus: saved.updated.paymentProofStatus,
      proofVersion: saved.updated.paymentProofVersion,
      chatForwardQueued: Boolean(saved.outboxEventId),
    });
  } catch (e) {
    console.error(JSON.stringify({
      event: "payment_proof_upload_failed",
      orderNumber,
      error: e instanceof Error ? e.message.slice(0, 300) : "unknown",
    }));
    return NextResponse.json(
      { error: "Upload bukti pembayaran gagal. Silakan coba lagi." },
      { status: 500 },
    );
  }
}
