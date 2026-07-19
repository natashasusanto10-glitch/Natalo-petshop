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

  // Best-effort mark-read (fix C2) — reset counter badge, jalan paralel dgn
  // query pesan. `.update()` (BUKAN `.set(..., {merge:true})`) sengaja: gagal
  // diam-diam (ditangkap di .catch) kalau room belum pernah ada, supaya GET
  // tak pernah membuat room stub tanpa `customerId` (invariant fix B2).
  // Perf/biaya: HANYA tulis kalau unread > 0 — baca dulu (1 read << 1 write)
  // lalu skip write bila tak perlu.
  const markRead = () =>
    (async () => {
      try {
        const roomSnap = await roomRef.get();
        const unread = roomSnap.exists
          ? ((roomSnap.data()?.unreadForCustomer as number | undefined) ?? 0)
          : 0;
        if (unread > 0) {
          await roomRef.update({ unreadForCustomer: 0 });
        }
      } catch {
        // best-effort — jangan gagalkan GET hanya karena mark-read.
      }
    })();

  const project = (
    doc: FirebaseFirestore.QueryDocumentSnapshot,
  ): CustomerMessage | null =>
    projectMessageForCustomer({ ...doc.data(), id: doc.id });

  // ── Mode MUNDUR (`?dir=older`) — pagination riwayat lama ─────────────
  // Klien app baru membuka room dengan mengambil HANYA halaman terbaru
  // (`?dir=older` tanpa `before`), lalu memuat pesan lebih lama saat scroll
  // ke atas (`?dir=older&before=<createdAt tertua yg sudah dimiliki>`). Ini
  // menggantikan pola lama "drain SEMUA halaman maju saat buka" yang bikin
  // puluhan round-trip berurutan sebelum layar tampil. Kontrak `?after=`
  // (polling maju) & default (klien app lama) DIBIARKAN utuh di bawah.
  if (request.nextUrl.searchParams.get("dir") === "older") {
    const beforeParam = request.nextUrl.searchParams.get("before");
    const beforeNum = beforeParam !== null ? Number(beforeParam) : null;
    const hasBefore = beforeNum !== null && Number.isFinite(beforeNum);
    const isLatestPage = !hasBefore;

    let query = messagesRef.orderBy("createdAt", "desc");
    if (hasBefore) {
      query = query.startAfter(beforeNum);
    }
    query = query.limit(PAGE_SIZE);

    // Mark-read HANYA saat mengambil halaman terbaru (user memang melihat
    // pesan terbaru) — memuat riwayat lama saat scroll ke atas TIDAK
    // menyentuh badge (menghemat 1 read+write room per halaman lama).
    const [snap] = await Promise.all([
      query.get(),
      isLatestPage ? markRead() : Promise.resolve(),
    ]);
    // Query desc → [terbaru ... tertua]. Dokumen RAW tertua di batch =
    // elemen terakhir; `prevCursor` (memuat yang lebih lama lagi) dihitung
    // dari RAW createdAt-nya supaya `startAfter` berikutnya melewati SEMUA
    // dokumen yang sudah diambil (termasuk yang di-drop allowlist).
    const rawDocs = snap.docs;
    const hasMoreOlder = rawDocs.length === PAGE_SIZE;
    const prevCursor = hasMoreOlder
      ? rawDocs[rawDocs.length - 1].data().createdAt
      : null;
    // Balik ke ASC untuk ditampilkan (list chat dari lama ke baru).
    const messages = rawDocs
      .slice()
      .reverse()
      .map(project)
      .filter((m): m is CustomerMessage => m !== null);

    return NextResponse.json({
      chatId: myChat,
      messages,
      prevCursor,
      // nextCursor tak dipakai di mode mundur — polling maju tetap lewat
      // `?after=` terpisah.
      nextCursor: null,
    });
  }

  // ── Mode MAJU (`?after=`) & default — polling + klien app lama ───────
  // Cursor `?after=<createdAt terakhir>` — kalau absen/tak valid, ambil
  // halaman pertama (fail-open, jangan 400 hanya karena cursor rusak).
  const afterParam = request.nextUrl.searchParams.get("after");
  const after = afterParam !== null ? Number(afterParam) : null;

  let query = messagesRef.orderBy("createdAt", "asc");
  if (after !== null && Number.isFinite(after)) {
    query = query.startAfter(after);
  }
  query = query.limit(PAGE_SIZE);

  const [snap] = await Promise.all([query.get(), markRead()]);
  const rawDocs = snap.docs;

  const messages = rawDocs
    .map(project)
    .filter((m): m is CustomerMessage => m !== null);

  // Fix (pagination correctness): "halaman penuh" & nilai cursor HARUS
  // dihitung dari RAW docs, bukan array `messages` yang sudah terproyeksi.
  // projectMessageForCustomer men-drop dokumen `staffOnly`; cursor dari pesan
  // terproyeksi terakhir bisa keliru & re-fetch dokumen yang sama.
  const hasMore = rawDocs.length === PAGE_SIZE;
  const nextCursor = hasMore ? rawDocs[rawDocs.length - 1].data().createdAt : null;

  return NextResponse.json({ chatId: myChat, messages, nextCursor });
}
