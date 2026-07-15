/**
 * POST /api/chat/send
 *
 * Customer mengirim pesan TEKS ke ruang chat tokochat
 * (`customerChats/cust_<userId>`). Gate WAJIB urut (lihat brief Task 5,
 * `docs/superpowers/plans/2026-07-07-customer-chat-plan-2-natalo-proxy.md`):
 *
 *   CSRF → session CUSTOMER → kill-switch → validasi body → rate-limit →
 *   snapshot Prisma → tulis pesan idempoten → auto-reopen (fix B1) →
 *   auto-greeting/away sekali per room (fix B7) → response.
 *
 * Auto-reopen & auto-greeting/away sengaja PROXY-owned (bukan Cloud
 * Function tokochat) — lihat komentar di `lib/chat/rooms.ts` (writeCustomerMessage
 * SENGAJA tidak menyentuh `status`/`greetingSentAt`). Helper efek samping
 * ini SHARED dengan `/api/chat/send-image` — lihat `lib/chat/auto-effects.ts`.
 */
import { NextRequest, NextResponse } from "next/server";
import { assertSameOrigin } from "@/lib/csrf";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { isChatEnabled } from "@/app/api/chat/config/route";
import { getTokochatFirestore } from "@/lib/chat/firestore-admin";
import { chatIdForUser, isValidClientMsgId, slidingWindowAllow } from "@/lib/chat/core";
import {
  buildCustomerSnapshot,
  writeCustomerMessage,
  type OrderAggregate,
} from "@/lib/chat/rooms";
import { autoReopenIfResolved, autoGreetingOrAwayIfNew } from "@/lib/chat/auto-effects";
import { buildOrderContextV1, type OrderContextV1 } from "@/lib/chat/order-contract";
import { CHAT_TEXT_MAX_LEN, validateChatSendContent } from "@/lib/chat/send-content";

export const dynamic = "force-dynamic";

const ROOM_COLLECTION = "customerChats";
const MESSAGE_SUBCOLLECTION = "messages";

const RATE_LIMIT_MAX = 20;
const RATE_LIMIT_WINDOW_MS = 60_000;
// Lookback lebih besar dari limit (20). Query di bawah SENGAJA tidak
// nge-filter `senderRole` di server (where + orderBy field beda butuh
// composite index baru yang belum ada di NLCHAT firestore.indexes.json —
// hanya ada `customerChats(status, lastMessageAt)`). Ambil N pesan
// terakhir (siapa pun pengirim), filter `senderRole === "customer"` di
// memory — cukup akurat untuk sliding window & tak butuh deploy index.
const RATE_LIMIT_LOOKBACK = 40;

type ProductContext = {
  productId: string;
  slug?: string;
  name: string;
  imageUrl?: string;
  price?: number;
  stock?: number;
};
type OrderContext = OrderContextV1;

type ParsedContext =
  | { type: "product"; productId: string }
  | { type: "order"; orderNumber: string }
  | null;

// Context dari body cuma dipakai untuk MENUNJUK produk/order mana — data
// tampilan (nama/harga/stok/status) SELALU diambil ulang dari Prisma di
// bawah, bukan dari client, supaya tak bisa dipalsukan (spoof) dan supaya
// order context di-scope ke order milik customer sendiri (anti-IDOR).
function parseContext(raw: unknown): ParsedContext {
  if (!raw || typeof raw !== "object") return null;
  const c = raw as Record<string, unknown>;
  if (c.type === "product" && typeof c.productId === "string" && c.productId.length > 0) {
    return { type: "product", productId: c.productId };
  }
  if (c.type === "order" && typeof c.orderNumber === "string" && c.orderNumber.length > 0) {
    return { type: "order", orderNumber: c.orderNumber };
  }
  return null;
}

type ReplyTo = { id: string; senderName?: string; type?: string; text?: string };

// Client HANYA boleh menunjuk id pesan yang dibalas — teks/senderName kutipan
// SELALU di-derive ulang dari pesan asli di Firestore (anti-spoof), sama
// disiplin dgn `context`. Kembalikan id mentah; derivasi di POST setelah
// snapshot siap (butuh customerName utk pesan customer sendiri).
function parseReplyToId(raw: unknown): string | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const id = typeof r.id === "string" ? r.id.trim() : "";
  return id.length > 0 && id.length <= 200 ? id : null;
}

// Preview singkat pesan yang dikutip — foto/produk diberi label, teks
// dipangkas. Dihitung SERVER dari doc pesan asli, bukan dari client.
function buildReplyPreview(msgData: Record<string, unknown>): string {
  const t = typeof msgData.type === "string" ? msgData.type : "text";
  if (t === "image") return "📷 Foto";
  if (t === "product" || t === "product_context") {
    const p = msgData.product as Record<string, unknown> | undefined;
    const name = p && typeof p.name === "string" ? p.name : "Produk";
    return `🛍️ ${name}`;
  }
  const text = typeof msgData.text === "string" ? msgData.text : "";
  return text.length > 200 ? `${text.slice(0, 200)}…` : text;
}

export async function POST(request: NextRequest) {
  // 1. CSRF — defense-in-depth di atas sameSite cookie.
  const csrf = assertSameOrigin(request);
  if (csrf) return csrf;

  // 2. Session — CUSTOMER (ADMIN juga lolos, lihat privilege elevation di lib/auth.ts).
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // 3. Kill-switch chat (app_settings/chatConfig).
  if (!(await isChatEnabled())) {
    return NextResponse.json({ error: "Chat sedang nonaktif." }, { status: 503 });
  }

  // 4. Parse + validasi body.
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }

  const b = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const text = typeof b.text === "string" ? b.text.trim() : "";
  const clientMsgId = b.clientMsgId;

  if (text.length > CHAT_TEXT_MAX_LEN || (!text && !parseContext(b.context))) {
    return NextResponse.json(
      {
        error: text.length > CHAT_TEXT_MAX_LEN
          ? "Pesan maksimal 4000 karakter."
          : "Pesan tidak boleh kosong tanpa konteks yang valid.",
      },
      { status: 400 },
    );
  }
  if (!isValidClientMsgId(clientMsgId)) {
    return NextResponse.json({ error: "clientMsgId tidak valid." }, { status: 400 });
  }
  const context = parseContext(b.context);
  const replyToId = parseReplyToId(b.replyTo);

  const firestore = getTokochatFirestore();
  const chatId = chatIdForUser(session.sub);
  const roomRef = firestore.collection(ROOM_COLLECTION).doc(chatId);
  const messagesRef = roomRef.collection(MESSAGE_SUBCOLLECTION);

  // 5. Rate-limit — sliding window dari timestamp pesan CUSTOMER terakhir
  // di room. Fail-open bila query Firestore error (jangan blokir customer
  // karena masalah infra).
  let recentTimestamps: number[] = [];
  try {
    const snap = await messagesRef.orderBy("createdAt", "desc").limit(RATE_LIMIT_LOOKBACK).get();
    recentTimestamps = snap.docs
      .filter((d) => d.data()?.senderRole === "customer")
      .map((d) => d.data()?.createdAt)
      .filter((v): v is number => typeof v === "number");
  } catch {
    recentTimestamps = [];
  }
  if (!slidingWindowAllow(recentTimestamps, Date.now(), RATE_LIMIT_MAX, RATE_LIMIT_WINDOW_MS)) {
    return NextResponse.json(
      { error: "Terlalu banyak pesan. Coba lagi sebentar lagi." },
      { status: 429 },
    );
  }

  // 6. Snapshot Prisma: user + agregat order ringan → buildCustomerSnapshot.
  const [user, orderAgg, lastOrderRow] = await Promise.all([
    prisma.user.findUnique({
      where: { id: session.sub },
      select: { name: true, phone: true },
    }),
    prisma.order.aggregate({
      // Exclude order yang bukan riwayat belanja "nyata" (batal/refund/belum
      // dibayar) supaya totalBelanja/orderCount yang dilihat staff tak
      // overstate — konsisten dgn semangat filter status di tempat lain
      // (mis. successfulOrderCount di app/api/orders/route.ts).
      where: { userId: session.sub, status: { notIn: ["CANCELLED", "REFUNDED", "PENDING"] } },
      _sum: { total: true },
      _count: true,
    }),
    prisma.order.findFirst({
      where: { userId: session.sub, status: { notIn: ["CANCELLED", "REFUNDED", "PENDING"] } },
      orderBy: { createdAt: "desc" },
      select: { orderNumber: true, status: true, total: true },
    }),
  ]);

  const orderAggregate: OrderAggregate = {
    totalBelanja: orderAgg._sum.total ?? 0,
    orderCount: orderAgg._count ?? 0,
    lastOrder: lastOrderRow
      ? { inv: lastOrderRow.orderNumber, status: lastOrderRow.status, total: lastOrderRow.total }
      : null,
  };
  const snapshot = buildCustomerSnapshot(user ?? {}, orderAggregate);

  // Context produk/order opsional — data tampilan diambil ulang dari
  // Prisma (bukan dari client) supaya tak bisa dipalsukan; order di-scope
  // ke `userId: session.sub` supaya customer tak bisa reference order
  // orang lain (anti-IDOR). Kalau tak ditemukan, context diam-diam
  // di-drop (bukan 400) — cuma metadata pelengkap, bukan bagian wajib.
  let productContext: ProductContext | undefined;
  let orderContext: OrderContext | undefined;
  if (context?.type === "product") {
    const product = await prisma.product.findUnique({
      where: { id: context.productId },
      select: {
        id: true,
        slug: true,
        name: true,
        imageUrl: true,
        price: true,
        discountPrice: true,
        stock: true,
      },
    });
    if (product) {
      productContext = {
        productId: product.id,
        slug: product.slug,
        name: product.name,
        imageUrl: product.imageUrl ?? undefined,
        price: product.discountPrice ?? product.price,
        stock: product.stock,
      };
    }
  } else if (context?.type === "order") {
    const order = await prisma.order.findFirst({
      where: { orderNumber: context.orderNumber, userId: session.sub },
      select: {
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
    if (order) {
      orderContext = buildOrderContextV1({ ...order, itemCount: order._count.items });
    }
  }

  const contentValidation = validateChatSendContent(
    text,
    Boolean(productContext || orderContext),
  );
  if (!contentValidation.ok) {
    return NextResponse.json({ error: contentValidation.error }, { status: 400 });
  }

  // 6b. Re-derive kutipan balasan dari pesan asli DI ROOM INI (anti-spoof +
  // anti-IDOR: baca `messagesRef.doc(id)` yang sudah di-scope ke chat customer
  // sendiri, jadi ia tak bisa mengutip pesan chat orang lain). senderName &
  // text preview dihitung server; bila pesan tak ada, kutipan di-drop diam2.
  let replyTo: ReplyTo | undefined;
  if (replyToId) {
    const refSnap = await messagesRef.doc(replyToId).get();
    if (refSnap.exists) {
      const rd = refSnap.data() as Record<string, unknown>;
      // staffOnly (catatan internal) TAK BOLEH dikutip ke pesan customer.
      if (rd.staffOnly !== true) {
        const rtype = typeof rd.type === "string" ? rd.type : "text";
        const who =
          rd.senderRole === "staff"
            ? (typeof rd.senderName === "string" && rd.senderName.trim()
                ? rd.senderName.trim()
                : "Admin")
            : snapshot.customerName || "Kamu";
        replyTo = {
          id: replyToId,
          senderName: who,
          type: rtype,
          text: buildReplyPreview(rd),
        };
      }
    }
  }

  // 7. Baca doc room SEBELUM writeCustomerMessage — state "before" dipakai
  // step 9 (auto-reopen) & step 10 (auto-greeting/away). writeCustomerMessage
  // sendiri tak menyentuh status/greetingSentAt (lihat lib/chat/rooms.ts).
  const roomSnapBefore = await roomRef.get();
  const roomDataBefore = roomSnapBefore.exists ? roomSnapBefore.data() : undefined;
  const wasResolved = roomDataBefore?.status === "resolved";
  const hadGreeting =
    !!roomDataBefore &&
    roomDataBefore.greetingSentAt !== undefined &&
    roomDataBefore.greetingSentAt !== null;
  const isNewRoom = !roomSnapBefore.exists;

  // 8. Tulis pesan customer (idempoten via clientMsgId; room merge di dalamnya).
  const writeResult = await writeCustomerMessage(
    { firestore, now: Date.now },
    {
      chatId,
      customerId: session.sub,
      senderRole: "customer",
      senderId: session.sub,
      senderName: snapshot.customerName || undefined,
      type: text ? "text" : orderContext ? "order_context" : "product_context",
      ...(text ? { text } : {}),
      clientMsgId,
      ...(productContext ? { product: productContext } : {}),
      ...(orderContext ? {
        order: orderContext.order,
        schemaVersion: orderContext.schemaVersion,
      } : {}),
      ...(replyTo ? { replyTo } : {}),
      customerName: snapshot.customerName,
      customerPhone: snapshot.customerPhone,
      summary: snapshot.summary,
      summaryUpdatedAt: snapshot.summaryUpdatedAt,
    },
  );

  // Efek samping (reopen/greeting/away/analytics) HANYA untuk penulisan
  // baru — retry pesan yang sama (deduped) tak boleh memicu ulang.
  if (!writeResult.deduped) {
    if (isNewRoom) {
      console.log(
        JSON.stringify({
          event: "customer_chat_created",
          chatId,
          customerId: session.sub,
          at: Date.now(),
        }),
      );
    }
    if (wasResolved) {
      await autoReopenIfResolved(firestore, chatId);
    }
    if (!hadGreeting) {
      const analyticsEvent = await autoGreetingOrAwayIfNew(firestore, chatId);
      if (analyticsEvent) {
        console.log(
          JSON.stringify({ event: analyticsEvent, chatId, customerId: session.sub, at: Date.now() }),
        );
      }
    }
  }

  // 11. Response.
  return NextResponse.json({
    ok: true,
    messageId: writeResult.messageId,
    deduped: writeResult.deduped,
  });
}
