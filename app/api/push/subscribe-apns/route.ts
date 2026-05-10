import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

/**
 * APNs token registration — dipanggil dari PushSubscribe.tsx saat user
 * di-iOS-native subscribe ke push.
 *
 * APNs token disimpan di table PushSubscription yang sama dengan Web Push,
 * dengan format `endpoint = "apns:<token>"` untuk dedup. Backend
 * lib/apns.ts akan detect prefix dan route via APNs HTTP/2 API
 * (sebaliknya Web Push pakai webpush library).
 */
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null);
  if (!body?.token || typeof body.token !== "string") {
    return NextResponse.json({ error: "Invalid token" }, { status: 400 });
  }

  const session = await getSession("CUSTOMER");
  const endpoint = `apns:${body.token}`;

  await prisma.pushSubscription.upsert({
    where: { endpoint },
    update: {
      // Untuk APNs, p256dh & auth di-set ke string kosong (gak relevan)
      // tapi field di schema NOT NULL jadi kita pakai placeholder.
      p256dh: "",
      auth: "",
      userId: session?.sub ?? null,
    },
    create: {
      endpoint,
      p256dh: "",
      auth: "",
      userId: session?.sub ?? null,
    },
  });

  return NextResponse.json({ ok: true });
}

export async function DELETE(req: NextRequest) {
  const body = await req.json().catch(() => null);
  if (!body?.token) {
    return NextResponse.json({ error: "token required" }, { status: 400 });
  }
  await prisma.pushSubscription
    .delete({ where: { endpoint: `apns:${body.token}` } })
    .catch(() => {});
  return NextResponse.json({ ok: true });
}
