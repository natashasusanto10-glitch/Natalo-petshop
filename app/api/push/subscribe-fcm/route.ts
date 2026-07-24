import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

/**
 * FCM token registration — dipanggil dari app-level push manager/settings
 * saat user Android native subscribe ke push.
 *
 * FCM token disimpan di table PushSubscription yang sama dengan Web Push
 * & APNs, dengan format `endpoint = "fcm:<token>"` untuk dedup. Backend
 * lib/fcm.ts detect prefix dan route via Firebase Admin SDK.
 */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null);
  if (!body?.token || typeof body.token !== "string") {
    return NextResponse.json({ error: "Invalid token" }, { status: 400 });
  }

  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const endpoint = `fcm:${body.token}`;

  const clientRender =
    typeof body.clientRender === "number" && Number.isInteger(body.clientRender)
      ? body.clientRender
      : null;

  await prisma.pushSubscription.upsert({
    where: { endpoint },
    update: {
      // Untuk FCM, p256dh & auth gak relevan (FCM pakai service-account auth
      // bukan VAPID keys). Schema field NOT NULL jadi pakai string kosong.
      p256dh: "",
      auth: "",
      userId: session.sub,
      clientRenderVersion: clientRender,
    },
    create: {
      endpoint,
      p256dh: "",
      auth: "",
      userId: session.sub,
      clientRenderVersion: clientRender,
    },
  });

  return NextResponse.json({ ok: true });
}

export async function DELETE(req: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await req.json().catch(() => null);
  if (!body?.token) {
    return NextResponse.json({ error: "token required" }, { status: 400 });
  }
  // Scope ke userId — attacker tidak bisa unsubscribe device user lain.
  await prisma.pushSubscription.deleteMany({
    where: { endpoint: `fcm:${body.token}`, userId: session.sub },
  });
  return NextResponse.json({ ok: true });
}
