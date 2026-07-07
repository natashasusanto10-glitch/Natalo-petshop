/**
 * POST /api/chat/send-image
 *
 * Customer mengirim FOTO ke ruang chat tokochat (`customerChats/cust_<userId>`).
 * Gate WAJIB urut (sama seperti Task 5 `/api/chat/send`, lihat brief
 * `docs/superpowers/plans/2026-07-07-customer-chat-plan-2-natalo-proxy.md`
 * Task 6):
 *
 *   CSRF → session CUSTOMER → kill-switch → validasi multipart (MIME/size/
 *   magic-byte) → clientMsgId → rate-limit → upload UploadThing →
 *   writeCustomerMessage idempoten → response.
 *
 * Pola multipart + magic-byte guard di-model dari
 * `app/api/feed/upload-photo/route.ts` (canonical pattern repo ini), size
 * limit lebih ketat (5 MB vs 8 MB feed) sesuai brief Task 6.
 *
 * Auto-reopen (fix B1) & auto-greeting/away (fix B7) IKUT disertakan di
 * sini — pakai helper SHARED dari `lib/chat/auto-effects.ts` (sama persis
 * yang dipakai `/api/chat/send`). Sebelumnya endpoint ini SENGAJA tidak
 * memicu efek itu, tapi review konsistensi lintas endpoint menemukan gap:
 * kalau customer HANYA kirim foto ke room `resolved`, room tak pernah
 * reopen sampai ada pesan teks. Sekarang balasan foto-saja pun reopen room
 * & (kalau room baru) memicu greeting/away, konsisten dgn endpoint teks.
 */
import { NextRequest, NextResponse } from "next/server";
import { assertSameOrigin } from "@/lib/csrf";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { isChatEnabled } from "@/app/api/chat/config/route";
import { getTokochatFirestore } from "@/lib/chat/firestore-admin";
import { uploadToUT } from "@/lib/uploadthing";
import { validateImageMagicBytes } from "@/lib/upload/validate-image-bytes";
import { chatIdForUser, isValidClientMsgId, slidingWindowAllow } from "@/lib/chat/core";
import { writeCustomerMessage } from "@/lib/chat/rooms";
import { autoReopenIfResolved, autoGreetingOrAwayIfNew } from "@/lib/chat/auto-effects";

export const dynamic = "force-dynamic";

const ROOM_COLLECTION = "customerChats";
const MESSAGE_SUBCOLLECTION = "messages";

const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const MAX_SIZE = 5 * 1024 * 1024; // 5 MB — lebih ketat dari feed (8 MB), foto chat dikirim via jaringan mobile customer

const RATE_LIMIT_MAX = 20;
const RATE_LIMIT_WINDOW_MS = 60_000;
// Sama seperti /api/chat/send — lookback pesan terakhir (bukan filter
// server-side senderRole, lihat komentar di route itu soal composite index
// yang belum ada), filter "customer" di memory.
const RATE_LIMIT_LOOKBACK = 40;

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

  // 4. Parse multipart + validasi file (MIME allowlist → size → magic-byte).
  const formData = await request.formData();
  const file = formData.get("file") as File | null;
  const clientMsgId = formData.get("clientMsgId");

  if (!file) {
    return NextResponse.json({ error: "Foto wajib." }, { status: 400 });
  }
  if (!ALLOWED_TYPES.has(file.type)) {
    return NextResponse.json(
      { error: "Format foto harus JPG, PNG, atau WebP." },
      { status: 400 },
    );
  }
  if (file.size > MAX_SIZE) {
    return NextResponse.json({ error: "Foto maksimal 5 MB." }, { status: 413 });
  }

  const buffer = Buffer.from(await file.arrayBuffer());
  if (!validateImageMagicBytes(buffer, file.type)) {
    return NextResponse.json(
      { error: "Isi foto tidak cocok dengan format gambar." },
      { status: 415 },
    );
  }

  if (!isValidClientMsgId(clientMsgId)) {
    return NextResponse.json({ error: "clientMsgId tidak valid." }, { status: 400 });
  }

  // chatId/customerId/senderId SELALU derive dari session.sub (anti-IDOR) —
  // tidak pernah dari input client, sama persis dgn /api/chat/send.
  const firestore = getTokochatFirestore();
  const chatId = chatIdForUser(session.sub);
  const roomRef = firestore.collection(ROOM_COLLECTION).doc(chatId);
  const messagesRef = roomRef.collection(MESSAGE_SUBCOLLECTION);

  // 5. Rate-limit (opsional per brief, tapi murah untuk disertakan — sama
  // pola dgn /api/chat/send). Dicek SEBELUM upload supaya spam tidak
  // membuang kuota/bandwidth UploadThing untuk request yang toh ditolak.
  // Fail-open bila query Firestore error (jangan blokir customer karena
  // masalah infra).
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

  // 6. Upload ke UploadThing.
  let url: string;
  try {
    const uploaded = await uploadToUT(file, `chat-${session.sub}`);
    url = uploaded.url;
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Upload gagal" },
      { status: 500 },
    );
  }

  // 7. Nama pengirim untuk tampilan staff — diambil dari Prisma (bukan
  // client) sama seperti buildCustomerSnapshot di /api/chat/send.
  const user = await prisma.user.findUnique({
    where: { id: session.sub },
    select: { name: true },
  });
  const senderName = user?.name || undefined;

  // 8. Baca doc room SEBELUM writeCustomerMessage — state "before" dipakai
  // step 10 (auto-reopen & auto-greeting/away), sama pola dgn /api/chat/send
  // (lihat komentar step 7 di sana). writeCustomerMessage sendiri tak
  // menyentuh status/greetingSentAt (lihat lib/chat/rooms.ts).
  const roomSnapBefore = await roomRef.get();
  const roomDataBefore = roomSnapBefore.exists ? roomSnapBefore.data() : undefined;
  const wasResolved = roomDataBefore?.status === "resolved";
  const hadGreeting =
    !!roomDataBefore &&
    roomDataBefore.greetingSentAt !== undefined &&
    roomDataBefore.greetingSentAt !== null;

  // 9. Tulis pesan customer (idempoten via clientMsgId; room merge di dalamnya).
  const writeResult = await writeCustomerMessage(
    { firestore, now: Date.now },
    {
      chatId,
      customerId: session.sub,
      senderRole: "customer",
      senderId: session.sub,
      senderName,
      type: "image",
      image: { url },
      clientMsgId,
    },
  );

  // 10. Efek samping (reopen/greeting/away) — SHARED dgn /api/chat/send
  // (lib/chat/auto-effects.ts), HANYA untuk penulisan baru — retry pesan
  // yang sama (deduped) tak boleh memicu ulang.
  if (!writeResult.deduped) {
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
    url,
    messageId: writeResult.messageId,
    deduped: writeResult.deduped,
  });
}
