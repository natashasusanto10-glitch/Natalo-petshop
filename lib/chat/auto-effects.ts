/**
 * Efek samping otomatis pasca-tulis-pesan-customer di ruang chat tokochat
 * (`customerChats/cust_<userId>`).
 *
 * SHARED antara `/api/chat/send` (teks) dan `/api/chat/send-image` (foto) —
 * diekstrak dari `/api/chat/send` (Task 5, fix B1/B7) supaya kedua endpoint
 * konsisten memicu reopen & greeting/away. Sebelum ekstraksi ini, hanya
 * endpoint teks yang memanggil helper ini — balasan FOTO-SAJA ke room
 * `resolved` tak pernah reopen (gap yang ditemukan review konsistensi lintas
 * endpoint). Perilaku/struktur transaksi TIDAK berubah dari versi asli,
 * hanya lokasinya (dan `roomRef`/`messagesRef` kini di-derive dari `chatId`
 * di dalam masing-masing fungsi, bukan dioper dari caller).
 */
import type { Firestore } from "firebase-admin/firestore";
import { computeChatHoursStatus } from "@/lib/chat/core";

const ROOM_COLLECTION = "customerChats";
const MESSAGE_SUBCOLLECTION = "messages";

const REOPEN_TEXT = "Percakapan dibuka kembali.";
const DEFAULT_GREETING_TEXT =
  "Halo! Terima kasih sudah menghubungi Natalo Petshop. Tim kami akan segera membalas pesanmu.";
// Fallback kalau app_settings/chatHours.awayMessage belum di-seed — sama
// dengan default template di Plan 6 (chat-settings seedDefaults()).
const DEFAULT_AWAY_TEMPLATE =
  "Halo! Kami sedang di luar jam operasional ({jamBuka}–{jamTutup}). Pesanmu akan kami balas segera.";

function formatAwayText(template: string, jamBuka: string | null, jamTutup: string | null): string {
  return template
    .replace(/\{jamBuka\}/g, jamBuka ?? "-")
    .replace(/\{jamTutup\}/g, jamTutup ?? "-");
}

/**
 * Fix B1: room lama berstatus "resolved" + customer kirim pesan baru →
 * otomatis reopen (`waiting_staff`) + system message, supaya staff sadar
 * ada balasan baru. Tanpa ini room tetap "resolved" & tak muncul di
 * antrian aktif staff (gap yang ditemukan review konsistensi).
 *
 * Re-check status DI DALAM transaksi (bukan cuma pakai snapshot "before"
 * dari luar) untuk menutup race window antara baca-sebelum dan transaksi.
 */
export async function autoReopenIfResolved(
  firestore: Firestore,
  chatId: string,
  now: () => number = Date.now,
): Promise<void> {
  const roomRef = firestore.collection(ROOM_COLLECTION).doc(chatId);
  const messagesRef = roomRef.collection(MESSAGE_SUBCOLLECTION);
  const sysRef = messagesRef.doc();
  await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(roomRef);
    const data = snap.exists ? snap.data() : undefined;
    if (!data || data.status !== "resolved") return; // sudah berubah (race) / bukan resolved lagi
    const ts = now();
    tx.set(
      roomRef,
      { status: "waiting_staff", statusChangedAt: ts, statusChangedBy: "system" },
      { merge: true },
    );
    tx.set(sysRef, {
      senderRole: "system",
      senderId: "system",
      type: "system",
      text: REOPEN_TEXT,
      auto: true,
      createdAt: ts,
      status: "sent",
    });
  });
}

/**
 * Fix B7 (PROXY-owned, bukan CF): kirim SATU pesan otomatis per room —
 * greeting (dalam jam operasional) atau away (di luar jam, template
 * `awayMessage` dari `app_settings/chatHours`, placeholder `{jamBuka}`/
 * `{jamTutup}`). `greetingSentAt` diset atomik di transaksi yang sama
 * (cegah dobel saat retry/race — re-check dilakukan di dalam transaksi,
 * bukan cuma dari snapshot "before" di luar).
 *
 * Return nama event analytics kalau benar-benar terkirim (bukan skip
 * akibat race), else `null`.
 */
export async function autoGreetingOrAwayIfNew(
  firestore: Firestore,
  chatId: string,
  now: () => number = Date.now,
): Promise<"auto_greeting_sent" | "auto_away_reply_sent" | null> {
  const roomRef = firestore.collection(ROOM_COLLECTION).doc(chatId);
  const messagesRef = roomRef.collection(MESSAGE_SUBCOLLECTION);

  let chatHoursDoc: Record<string, unknown> | undefined;
  try {
    const hoursSnap = await firestore.doc("app_settings/chatHours").get();
    chatHoursDoc = hoursSnap.exists ? (hoursSnap.data() as Record<string, unknown>) : undefined;
  } catch {
    chatHoursDoc = undefined; // fail-open: computeChatHoursStatus(undefined, ...) → offline default
  }

  const hours = computeChatHoursStatus(chatHoursDoc, now());
  const isOnline = hours.online;
  const awayTemplate =
    typeof chatHoursDoc?.awayMessage === "string" && chatHoursDoc.awayMessage.length > 0
      ? chatHoursDoc.awayMessage
      : DEFAULT_AWAY_TEMPLATE;
  const text = isOnline
    ? DEFAULT_GREETING_TEXT
    : formatAwayText(awayTemplate, hours.todayOpen, hours.todayClose);

  const sysRef = messagesRef.doc();
  const sent = await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(roomRef);
    const data = snap.exists ? snap.data() : undefined;
    if (data && data.greetingSentAt !== undefined && data.greetingSentAt !== null) {
      return false; // sudah dikirim (race/retry) — jangan dobel
    }
    const ts = now();
    tx.set(roomRef, { greetingSentAt: ts }, { merge: true });
    tx.set(sysRef, {
      senderRole: "system",
      senderId: "system",
      type: "system",
      text,
      auto: true,
      createdAt: ts,
      status: "sent",
    });
    return true;
  });

  if (!sent) return null;
  return isOnline ? "auto_greeting_sent" : "auto_away_reply_sent";
}
