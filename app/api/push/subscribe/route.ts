import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { getSession } from "@/lib/auth";

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null);

  // Diagnostic log — visible di Vercel Logs "[push-trace]" untuk tracking
  // web push subscribe flow. Cek body shape + endpoint prefix.
  console.log(
    "[push-trace]",
    JSON.stringify({
      event: "subscribe-endpoint-hit",
      hasBody: !!body,
      hasEndpoint: !!body?.endpoint,
      hasKeys: !!body?.keys,
      hasP256dh: !!body?.keys?.p256dh,
      hasAuth: !!body?.keys?.auth,
      endpointPrefix: body?.endpoint?.slice(0, 30) + "...",
    })
  );

  if (!body?.endpoint || !body?.keys?.p256dh || !body?.keys?.auth) {
    console.log(
      "[push-trace]",
      JSON.stringify({ event: "subscribe-invalid-shape" })
    );
    return NextResponse.json(
      { error: "Invalid subscription" },
      { status: 400 }
    );
  }

  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    console.log(
      "[push-trace]",
      JSON.stringify({
        event: "subscribe-unauthorized",
        hasSession: !!session,
        role: session?.role,
      })
    );
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  await prisma.pushSubscription.upsert({
    where: { endpoint: body.endpoint },
    update: {
      p256dh: body.keys.p256dh,
      auth: body.keys.auth,
      userId: session.sub,
    },
    create: {
      endpoint: body.endpoint,
      p256dh: body.keys.p256dh,
      auth: body.keys.auth,
      userId: session.sub,
    },
  });

  console.log(
    "[push-trace]",
    JSON.stringify({
      event: "subscribe-saved",
      userTag: "user:" + session.sub.slice(-6),
      endpointPrefix: body.endpoint.slice(0, 30) + "...",
    })
  );

  return NextResponse.json({ ok: true });
}

export async function DELETE(req: NextRequest) {
  const body = await req.json().catch(() => null);
  if (!body?.endpoint)
    return NextResponse.json({ error: "endpoint required" }, { status: 400 });
  await prisma.pushSubscription
    .delete({ where: { endpoint: body.endpoint } })
    .catch(() => {});
  return NextResponse.json({ ok: true });
}
