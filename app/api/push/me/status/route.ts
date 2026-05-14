/**
 * GET /api/push/me/status
 *
 * Diagnostic-only: kasih tau user yang sedang login berapa subscription
 * miliknya per channel (web/apns/fcm). Berguna untuk debug "kenapa
 * push gak nyampe HP" tanpa butuh akses DB.
 *
 * Hit dari device:
 *   curl -b "natalo-member-session=<token>" https://.../api/push/me/status
 *
 * Atau buka URL ini langsung di browser native iOS / Safari setelah login.
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

export async function GET() {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const userId = session.sub;
  const mine = await prisma.pushSubscription.findMany({
    where: { userId },
    select: { id: true, endpoint: true, createdAt: true },
  });

  const anonymous = await prisma.pushSubscription.count({
    where: { userId: null },
  });

  const channels = {
    web: mine.filter((s) => s.endpoint.startsWith("https://")).length,
    apns: mine.filter((s) => s.endpoint.startsWith("apns:")).length,
    fcm: mine.filter((s) => s.endpoint.startsWith("fcm:")).length,
  };

  const apnsConfigured = Boolean(
    process.env.APNS_KEY_ID &&
      process.env.APNS_TEAM_ID &&
      process.env.APNS_KEY_CONTENT,
  );
  const fcmConfigured = Boolean(
    process.env.FCM_PROJECT_ID &&
      process.env.FCM_CLIENT_EMAIL &&
      process.env.FCM_PRIVATE_KEY,
  );
  const webPushConfigured = Boolean(
    process.env.VAPID_PUBLIC_KEY && process.env.VAPID_PRIVATE_KEY,
  );

  return NextResponse.json({
    userId,
    channels,
    totalMine: mine.length,
    anonymousCount: anonymous,
    serverConfig: {
      apns: apnsConfigured,
      fcm: fcmConfigured,
      webPush: webPushConfigured,
      apnsProduction: process.env.APNS_PRODUCTION === "true",
      apnsBundleId: process.env.APNS_BUNDLE_ID || "com.natalo.petshop",
    },
    subscriptions: mine.map((s) => ({
      id: s.id,
      endpointHint:
        s.endpoint.length > 24
          ? `${s.endpoint.slice(0, 12)}…${s.endpoint.slice(-8)}`
          : s.endpoint,
      createdAt: s.createdAt,
    })),
  });
}
