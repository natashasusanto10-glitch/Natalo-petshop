import { NextResponse } from "next/server";
import { getTokochatFirestore } from "@/lib/chat/firestore-admin";
import { parseChatEnabled, computeChatHoursStatus } from "@/lib/chat/core";

export const dynamic = "force-dynamic";

export async function isChatEnabled(): Promise<boolean> {
  try {
    const snap = await getTokochatFirestore().doc("app_settings/chatConfig").get();
    return parseChatEnabled(snap.exists ? snap.data() : undefined);
  } catch {
    // Fail-open: jika config tak terbaca, jangan matikan chat karena error infra.
    return true;
  }
}

// fix B3: status "Online / Di luar jam operasional" untuk header chat customer,
// dihitung server-side dari app_settings/chatHours (WIB) — Plan 4 tinggal render.
export async function getHoursStatus() {
  try {
    const snap = await getTokochatFirestore().doc("app_settings/chatHours").get();
    return computeChatHoursStatus(snap.exists ? snap.data() : undefined, Date.now());
  } catch {
    return { online: true, timezone: "Asia/Jakarta", todayOpen: null, todayClose: null };
  }
}

export async function GET() {
  const [chatEnabled, hours] = await Promise.all([isChatEnabled(), getHoursStatus()]);
  return NextResponse.json({ chatEnabled, online: hours.online, hours });
}
