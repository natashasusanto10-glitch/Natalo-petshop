import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

/**
 * POST /api/admin/push/register-fcm
 *
 * Register FCM token admin (dari flutter_admin/) ke PushSubscription
 * table. Endpoint identik flow customer /api/push/subscribe-fcm tapi
 * pakai admin session — supaya admin dapat push notif untuk event:
 *   - Order baru masuk
 *   - Customer minta cancel
 *   - Feed customer post pending review
 *   - Voucher abuse high severity
 *
 * Token disimpan dgn prefix `fcm:` di endpoint field; userId = admin
 * session sub. Backend lib/fcm.ts detect prefix dan kirim via
 * Firebase Admin SDK.
 */
export async function POST(req: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await req.json().catch(() => null);
  const token = body?.token;
  if (!token || typeof token !== "string") {
    return NextResponse.json({ error: "Invalid token" }, { status: 400 });
  }

  const endpoint = `fcm:${token}`;
  await prisma.pushSubscription.upsert({
    where: { endpoint },
    update: {
      p256dh: "",
      auth: "",
      userId: session.sub,
    },
    create: {
      endpoint,
      p256dh: "",
      auth: "",
      userId: session.sub,
    },
  });

  return NextResponse.json({ ok: true });
}

export async function DELETE(req: NextRequest) {
  const session = await getSession("ADMIN");
  if (!session || session.role !== "ADMIN") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await req.json().catch(() => null);
  if (!body?.token) {
    return NextResponse.json({ error: "token required" }, { status: 400 });
  }
  await prisma.pushSubscription.deleteMany({
    where: { endpoint: `fcm:${body.token}`, userId: session.sub },
  });
  return NextResponse.json({ ok: true });
}
