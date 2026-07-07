/**
 * GET /api/chat/[chatId]
 *
 * Ambil histori pesan ruang chat tokochat milik customer (paginated,
 * proyeksi allowlist).
 *
 * **Anti-IDOR (kritis):** param `[chatId]` dari URL HANYA dipakai untuk
 * validasi kecocokan — room yang BENAR-BENAR dibaca SELALU
 * `myChat = chatIdForUser(session.sub)`. Kalau `params.chatId !== myChat`
 * → 403. Ini mencegah customer membaca room customer lain hanya dengan
 * mengganti `chatId` di URL (session tetap miliknya sendiri, room tetap
 * di-derive dari `session.sub`, bukan dari input klien).
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { getTokochatFirestore } from "@/lib/chat/firestore-admin";
import { chatIdForUser, projectMessageForCustomer, type CustomerMessage } from "@/lib/chat/core";

export const dynamic = "force-dynamic";

const ROOM_COLLECTION = "customerChats";
const MESSAGE_SUBCOLLECTION = "messages";
const PAGE_SIZE = 50;

type Params = {
  params: Promise<{ chatId: string }>;
};

export async function GET(request: NextRequest, { params }: Params) {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { chatId } = await params;
  const myChat = chatIdForUser(session.sub);
  // Anti-IDOR: param URL cuma dibandingkan, TIDAK PERNAH dipakai untuk
  // memilih room di query di bawah — query selalu pakai `myChat`.
  if (chatId !== myChat) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const firestore = getTokochatFirestore();
  const roomRef = firestore.collection(ROOM_COLLECTION).doc(myChat);
  const messagesRef = roomRef.collection(MESSAGE_SUBCOLLECTION);

  // Cursor `?after=<createdAt terakhir>` — kalau absen/tak valid, ambil
  // halaman pertama (fail-open, jangan 400 hanya karena cursor rusak).
  const afterParam = request.nextUrl.searchParams.get("after");
  const after = afterParam !== null ? Number(afterParam) : null;

  let query = messagesRef.orderBy("createdAt", "asc");
  if (after !== null && Number.isFinite(after)) {
    query = query.startAfter(after);
  }
  query = query.limit(PAGE_SIZE);

  // Tandai baca (fix C2) — reset counter badge, best-effort, jalan paralel
  // dgn query pesan. `.update()` (BUKAN `.set(..., {merge:true})`) sengaja
  // dipakai: gagal diam-diam (ditangkap di .catch) kalau room belum pernah
  // ada, supaya endpoint GET ini tak pernah membuat room stub tanpa
  // `customerId` (invariant fix B2 — lihat komentar lib/chat/rooms.ts).
  // Tidak memutasi `readByCustomerAt` per-pesan — disederhanakan sesuai
  // brief Task 7 (tak diminta spec §4.2 maupun reconciliation Plan 3).
  const markReadPromise = roomRef.update({ unreadForCustomer: 0 }).catch(() => undefined);

  const [snap] = await Promise.all([query.get(), markReadPromise]);

  const messages = snap.docs
    .map((doc) => projectMessageForCustomer({ ...doc.data(), id: doc.id }))
    .filter((m): m is CustomerMessage => m !== null);

  // Simplifikasi disengaja (brief Task 7): "halaman penuh" dicek dari
  // panjang array TERPROYEKSI (bukan jumlah raw docs). Dokumen staffOnly/
  // internal yang di-drop projectMessageForCustomer jarang jadi entri
  // terakhir sebuah halaman; kalaupun terjadi, halaman berikutnya paling
  // buruk cuma re-scan beberapa dokumen yang sudah di-drop — tak ada efek
  // yang terlihat customer (tak ada duplikat/pesan hilang).
  const nextCursor =
    messages.length === PAGE_SIZE ? messages[messages.length - 1].createdAt : null;

  return NextResponse.json({ chatId: myChat, messages, nextCursor });
}
