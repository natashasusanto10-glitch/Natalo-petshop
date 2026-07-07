/**
 * GET /api/chat/unread
 *
 * Badge unread pesan staff→customer untuk `AppChatButton` (Plan 4). Baca
 * `unreadForCustomer` dari room `customerChats/{chatIdForUser(session.sub)}`
 * — field ini di-increment oleh Cloud Function tokochat (Plan 3) saat staff
 * membalas, dan di-reset ke 0 oleh `GET /api/chat/[chatId]` (fix C2) saat
 * customer membuka chat.
 *
 * Room SELALU di-derive dari session (`chatIdForUser(session.sub)`), tak
 * ada parameter `chatId` dari klien sama sekali di endpoint ini — tak ada
 * permukaan IDOR untuk dijaga di sini.
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { chatIdForUser } from "@/lib/chat/core";
import { getTokochatFirestore } from "@/lib/chat/firestore-admin";

export const dynamic = "force-dynamic";

const ROOM_COLLECTION = "customerChats";

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const chatId = chatIdForUser(session.sub);
  const roomSnap = await getTokochatFirestore().collection(ROOM_COLLECTION).doc(chatId).get();
  const data = roomSnap.exists ? roomSnap.data() : undefined;
  const unreadForCustomer =
    typeof data?.unreadForCustomer === "number" ? data.unreadForCustomer : 0;

  return NextResponse.json({ unreadForCustomer });
}
