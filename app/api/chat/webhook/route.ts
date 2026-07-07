/**
 * POST /api/chat/webhook
 *
 * Dipanggil oleh Cloud Function tokochat (Plan 3, `notifyNewCustomerMessage`)
 * saat pesan STAFF baru ditulis di `customerChats/{chatId}/messages/*` —
 * proxy ini mengirim FCM push ke app Natalo customer supaya notifikasi
 * muncul di HP.
 *
 * Ini endpoint SERVER-TO-SERVER (CF tokochat → proxy Next.js), BUKAN
 * dipanggil browser customer. Otentikasi via shared-secret HMAC
 * (`x-chat-signature` = HMAC_SHA256(rawBody, CHAT_WEBHOOK_SECRET) hex,
 * lihat `verifyWebhookSignature` di `lib/chat/core.ts`) — SENGAJA tidak
 * pakai session/CSRF (tak ada cookie browser di request server-to-server).
 *
 * Kontrak body (final, Plan 2 Task 8 + Plan 3):
 *   { chatId, customerUserId, messageId, preview, senderName }
 *
 * Idempotensi: sebelum kirim FCM, coba `create()` doc penanda
 * `customerChats/{chatId}/webhookSeen/{messageId}`. `create()` gagal (doc
 * sudah ada) → request ini adalah retry/duplikat (CF Cloud Functions bisa
 * retry at-least-once) → balas 200 `{ deduped: true }` TANPA kirim FCM lagi.
 */
import { NextRequest, NextResponse } from "next/server";
import { verifyWebhookSignature } from "@/lib/chat/core";
import { getTokochatFirestore } from "@/lib/chat/firestore-admin";
import { sendFcmToUser } from "@/lib/fcm";

export const dynamic = "force-dynamic";

const SIGNATURE_HEADER = "x-chat-signature";
const ROOM_COLLECTION = "customerChats";
const SEEN_SUBCOLLECTION = "webhookSeen";

export type WebhookPayload = {
  chatId: string;
  customerUserId: string;
  messageId: string;
  preview: string;
  senderName?: string;
};

// Helper MURNI (bisa diuji tanpa I/O) — parse raw JSON body webhook +
// validasi field wajib. `senderName` opsional (route fallback ke "Natalo").
// Return `null` bila raw bukan JSON valid, bukan object, atau field wajib
// (chatId/customerUserId/messageId/preview) hilang/bukan string.
export function parseWebhookPayload(raw: string): WebhookPayload | null {
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;

  const b = body as Record<string, unknown>;
  if (typeof b.chatId !== "string" || b.chatId.length === 0) return null;
  if (typeof b.customerUserId !== "string" || b.customerUserId.length === 0) return null;
  if (typeof b.messageId !== "string" || b.messageId.length === 0) return null;
  if (typeof b.preview !== "string") return null;

  const payload: WebhookPayload = {
    chatId: b.chatId,
    customerUserId: b.customerUserId,
    messageId: b.messageId,
    preview: b.preview,
  };
  if (typeof b.senderName === "string" && b.senderName.length > 0) {
    payload.senderName = b.senderName;
  }
  return payload;
}

export async function POST(request: NextRequest) {
  // Raw body WAJIB dibaca sebelum parse JSON — HMAC dihitung atas exact
  // bytes yang dikirim CF, bukan hasil re-serialize `request.json()` (bisa
  // beda whitespace/key order → signature mismatch).
  const raw = await request.text();
  const signature = request.headers.get(SIGNATURE_HEADER) ?? "";
  const secret = process.env.CHAT_WEBHOOK_SECRET ?? "";

  if (!verifyWebhookSignature(raw, signature, secret)) {
    return NextResponse.json({ error: "Invalid signature" }, { status: 401 });
  }

  const payload = parseWebhookPayload(raw);
  if (!payload) {
    return NextResponse.json({ error: "Invalid payload" }, { status: 400 });
  }
  const { chatId, customerUserId, messageId, preview, senderName } = payload;

  // Idempotensi: `create()` gagal (doc sudah ada) -> ini retry/duplikat dari
  // CF (at-least-once delivery) -> jangan kirim FCM dua kali untuk pesan yang sama.
  const firestore = getTokochatFirestore();
  const seenRef = firestore
    .collection(ROOM_COLLECTION)
    .doc(chatId)
    .collection(SEEN_SUBCOLLECTION)
    .doc(messageId);

  try {
    await seenRef.create({ seenAt: Date.now() });
  } catch {
    return NextResponse.json({ deduped: true });
  }

  await sendFcmToUser(customerUserId, {
    title: senderName ?? "Natalo",
    body: preview,
    url: "/chat",
    tag: `chat-${chatId}`,
    data: { type: "customer_chat", chatId },
  });

  return NextResponse.json({ ok: true });
}
