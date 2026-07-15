import { prisma } from "@/lib/prisma";
import { getTokochatFirestore } from "@/lib/chat/firestore-admin";
import { chatIdForUser } from "@/lib/chat/core";
import { isOrderContextV1, type OrderContextV1 } from "@/lib/chat/order-contract";
import { upsertOrderContextMessage } from "@/lib/chat/rooms";

export const ORDER_CONTEXT_OUTBOX_TYPE = "ORDER_CONTEXT_UPSERT_V1";

export type OrderContextOutboxPayload = OrderContextV1 & {
  orderId: string;
  customerId: string;
};

export function orderContextOutboxKey(orderId: string): string {
  return `payment-proof:${orderId}`;
}

export function parseOrderContextOutboxPayload(value: unknown): OrderContextOutboxPayload | null {
  if (!isOrderContextV1(value)) return null;
  const root = value as Record<string, unknown>;
  if (typeof root.orderId !== "string" || root.orderId.length === 0) return null;
  if (typeof root.customerId !== "string" || root.customerId.length === 0) return null;
  return value as OrderContextOutboxPayload;
}

function safeError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.replace(/[\r\n\t]+/g, " ").slice(0, 500);
}

function retryAt(attempts: number): Date {
  const seconds = Math.min(15 * 2 ** Math.max(0, attempts - 1), 60 * 60);
  return new Date(Date.now() + seconds * 1000);
}

export async function processOrderContextOutboxEvent(eventId: string): Promise<boolean> {
  const event = await prisma.chatOutboxEvent.findUnique({
    where: { id: eventId },
    select: {
      id: true,
      type: true,
      payload: true,
      generation: true,
      status: true,
      attempts: true,
      availableAt: true,
    },
  });
  if (!event || event.type !== ORDER_CONTEXT_OUTBOX_TYPE) return false;
  if (!(["PENDING", "FAILED"] as const).includes(event.status as "PENDING" | "FAILED")) {
    return event.status === "PROCESSED";
  }
  if (event.availableAt.getTime() > Date.now()) return false;

  const claim = await prisma.chatOutboxEvent.updateMany({
    where: {
      id: event.id,
      generation: event.generation,
      status: { in: ["PENDING", "FAILED"] },
      availableAt: { lte: new Date() },
    },
    data: { status: "PROCESSING", lockedAt: new Date(), attempts: { increment: 1 } },
  });
  if (claim.count !== 1) return false;

  try {
    const payload = parseOrderContextOutboxPayload(event.payload);
    if (!payload) throw new Error("Invalid ORDER_CONTEXT_UPSERT_V1 payload");

    const result = await upsertOrderContextMessage(
      { firestore: getTokochatFirestore(), now: Date.now },
      {
        chatId: chatIdForUser(payload.customerId),
        customerId: payload.customerId,
        orderId: payload.orderId,
        schemaVersion: payload.schemaVersion,
        order: payload.order,
      },
    );

    await prisma.chatOutboxEvent.updateMany({
      where: { id: event.id, generation: event.generation, status: "PROCESSING" },
      data: {
        status: "PROCESSED",
        processedAt: new Date(),
        lockedAt: null,
        lastError: null,
      },
    });
    console.info(JSON.stringify({
      event: result.created ? "order_context_forwarded" : "order_context_deduped",
      outboxEventId: event.id,
      orderNumber: payload.order.orderNumber,
      proofVersion: payload.order.proofVersion,
      messageId: result.messageId,
      attempt: event.attempts + 1,
    }));
    return true;
  } catch (error) {
    const message = safeError(error);
    await prisma.chatOutboxEvent.updateMany({
      where: { id: event.id, generation: event.generation, status: "PROCESSING" },
      data: {
        status: "FAILED",
        lockedAt: null,
        availableAt: retryAt(event.attempts + 1),
        lastError: message,
      },
    });
    console.error(JSON.stringify({
      event: "payment_proof_forward_failed",
      outboxEventId: event.id,
      attempt: event.attempts + 1,
      error: message,
    }));
    return false;
  }
}

export async function processOrderContextOutboxBatch(limit = 25): Promise<{
  scanned: number;
  processed: number;
}> {
  const now = new Date();
  // Recover workers interrupted after claiming an event. Generation guards
  // prevent an older worker from completing over a newer proof upload.
  await prisma.chatOutboxEvent.updateMany({
    where: {
      type: ORDER_CONTEXT_OUTBOX_TYPE,
      status: "PROCESSING",
      lockedAt: { lt: new Date(now.getTime() - 5 * 60 * 1000) },
    },
    data: { status: "FAILED", lockedAt: null, availableAt: now, lastError: "stale worker claim" },
  });
  const events = await prisma.chatOutboxEvent.findMany({
    where: {
      type: ORDER_CONTEXT_OUTBOX_TYPE,
      status: { in: ["PENDING", "FAILED"] },
      availableAt: { lte: now },
    },
    orderBy: { availableAt: "asc" },
    take: Math.min(Math.max(limit, 1), 100),
    select: { id: true },
  });
  let processed = 0;
  for (const event of events) {
    if (await processOrderContextOutboxEvent(event.id)) processed += 1;
  }
  return { scanned: events.length, processed };
}
