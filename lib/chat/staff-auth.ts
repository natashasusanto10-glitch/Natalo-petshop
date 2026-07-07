import { NextResponse } from "next/server";
import { getTokochatAuth, getTokochatFirestore } from "@/lib/chat/firestore-admin";

export function isStaffAuthorized(
  userDoc: { role?: string; canHandleCustomer?: boolean } | null,
): boolean {
  if (!userDoc) return false;
  return userDoc.role === "owner" || userDoc.canHandleCustomer === true;
}

export async function verifyStaffRequest(
  request: Request,
): Promise<{ uid: string } | NextResponse> {
  const header = request.headers.get("authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) return NextResponse.json({ error: "Token wajib." }, { status: 401 });
  let uid: string;
  try {
    uid = (await getTokochatAuth().verifyIdToken(token)).uid;
  } catch {
    return NextResponse.json({ error: "Token tidak valid." }, { status: 401 });
  }
  const snap = await getTokochatFirestore().doc(`users/${uid}`).get();
  if (!isStaffAuthorized(snap.exists ? (snap.data() as Record<string, unknown>) : null)) {
    return NextResponse.json({ error: "Tidak berhak menangani customer." }, { status: 403 });
  }
  return { uid };
}
