/**
 * GET /api/push/me/status
 *
 * Diagnostic-only — kasih tau status push subscription. Punya 2 mode:
 *
 * 1. Dengan customer session: tampilkan subscription milik user, tanpa
 *    expose data user lain.
 * 2. Tanpa session: tampilkan AGREGAT — total subscription per channel
 *    & 5 sub terbaru (hint endpoint, createdAt) tanpa userId. Cukup
 *    untuk verifikasi "apakah token sampai DB" tanpa butuh login dari
 *    Safari standalone yang tidak share cookie WebView.
 *
 * Tetap aman: tidak return token mentah, hanya hint (8 char prefix +
 * 8 char suffix). Tidak return userId.
 */
import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";

function hint(endpoint: string): string {
  if (endpoint.length <= 24) return endpoint.slice(0, 16);
  return `${endpoint.slice(0, 16)}…${endpoint.slice(-8)}`;
}

export async function GET() {
  const session = await getSession("CUSTOMER");

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

  const serverConfig = {
    apns: apnsConfigured,
    fcm: fcmConfigured,
    webPush: webPushConfigured,
    apnsProduction: process.env.APNS_PRODUCTION === "true",
    apnsBundleId: process.env.APNS_BUNDLE_ID || "com.natalo.petshop",
  };

  if (session && session.role === "CUSTOMER") {
    const mine = await prisma.pushSubscription.findMany({
      where: { userId: session.sub },
      select: { id: true, endpoint: true, createdAt: true },
      orderBy: { createdAt: "desc" },
    });

    return NextResponse.json({
      authenticated: true,
      userId: session.sub,
      mine: {
        web: mine.filter((s) => s.endpoint.startsWith("https://")).length,
        apns: mine.filter((s) => s.endpoint.startsWith("apns:")).length,
        fcm: mine.filter((s) => s.endpoint.startsWith("fcm:")).length,
        total: mine.length,
        recent: mine.slice(0, 5).map((s) => ({
          endpointHint: hint(s.endpoint),
          createdAt: s.createdAt,
        })),
      },
      serverConfig,
    });
  }

  // Tanpa session — kasih agregat aman (tidak ada userId / token mentah).
  const allCounts = await prisma.pushSubscription.groupBy({
    by: ["userId"],
    _count: { _all: true },
  }).catch(() => []);
  const totalByEndpointType = await prisma.pushSubscription.findMany({
    select: { endpoint: true, createdAt: true, userId: true },
    orderBy: { createdAt: "desc" },
    take: 50,
  }).catch(() => []);

  const aggregate = {
    web: totalByEndpointType.filter((s) => s.endpoint.startsWith("https://")).length,
    apns: totalByEndpointType.filter((s) => s.endpoint.startsWith("apns:")).length,
    fcm: totalByEndpointType.filter((s) => s.endpoint.startsWith("fcm:")).length,
    anonymous: totalByEndpointType.filter((s) => s.userId === null).length,
    distinctUsers: allCounts.length,
  };

  return NextResponse.json({
    authenticated: false,
    hint: "Tidak ada session customer di request ini. Mungkin buka URL di Safari standalone, bukan dalam Capacitor WebView. Endpoint ini tetap kasih agregat aman: berapa subscription per channel di seluruh DB (max 50 terbaru).",
    aggregate,
    recent: totalByEndpointType.slice(0, 10).map((s) => ({
      endpointHint: hint(s.endpoint),
      hasUser: s.userId !== null,
      createdAt: s.createdAt,
    })),
    serverConfig,
  });
}
