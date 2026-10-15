import { NextResponse } from "next/server";
import { getTokochatAuth, getTokochatFirestore } from "@/lib/chat/firestore-admin";

type StaffUserDoc = {
  role?: string;
  canHandleCustomer?: boolean;
  canVerifyPayments?: boolean;
  nama?: unknown;
  name?: unknown;
};

export function staffDisplayName(doc: { nama?: unknown; name?: unknown } | null): string {
  const raw = typeof doc?.nama === "string" ? doc.nama : typeof doc?.name === "string" ? doc.name : "";
  const clean = raw.trim().slice(0, 60);
  return clean || "Staf toko";
}

export function isStaffAuthorized(
  userDoc: StaffUserDoc | null,
): boolean {
  if (!userDoc) return false;
  return userDoc.role === "owner" || userDoc.canHandleCustomer === true;
}

export function isPaymentStaffAuthorized(
  userDoc: StaffUserDoc | null,
): boolean {
  if (!userDoc) return false;
  return userDoc.role === "owner" || userDoc.canVerifyPayments === true;
}

async function verifyStaffWith(
  request: Request,
  authorize: (userDoc: StaffUserDoc | null) => boolean,
  forbiddenMessage: string,
): Promise<{ uid: string; name: string } | NextResponse> {
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
  const userDoc = snap.exists ? (snap.data() as StaffUserDoc) : null;
  if (!authorize(userDoc)) {
    return NextResponse.json({ error: forbiddenMessage }, { status: 403 });
  }
  return { uid, name: staffDisplayName(userDoc) };
}

export async function verifyStaffRequest(
  request: Request,
): Promise<{ uid: string; name: string } | NextResponse> {
  return verifyStaffWith(request, isStaffAuthorized, "Tidak berhak menangani customer.");
}

export async function verifyPaymentStaffRequest(
  request: Request,
): Promise<{ uid: string; name: string } | NextResponse> {
  return verifyStaffWith(
    request,
    isPaymentStaffAuthorized,
    "Tidak berhak memverifikasi pembayaran.",
  );
}
