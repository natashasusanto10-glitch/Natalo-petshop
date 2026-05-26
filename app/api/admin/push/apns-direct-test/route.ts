/**
 * POST /api/admin/push/apns-direct-test
 *
 * DIAGNOSTIC — bypass Firebase Cloud Messaging entirely. Sign JWT
 * dengan `.p8` di Vercel env (APNS_KEY_ID + APNS_KEY_CONTENT + APNS_TEAM_ID)
 * dan kirim langsung ke Apple APNs server. Get exact response code dari
 * Apple — apakah BadDeviceToken, InvalidProviderToken, TopicDisallowed,
 * atau success.
 *
 * Berguna untuk debug kasus "Firebase Admin SDK report ok tapi device
 * gak terima notif" — Firebase silent-fail kalau APNs reject downstream.
 *
 * Body:
 *   { userId: string, title?: string, body?: string }
 *
 * Response:
 *   {
 *     ok,
 *     adminUserId,
 *     targetUserId,
 *     apnsTokensFound: number,
 *     results: [{
 *       tokenHint, status, sentCount?, reason?, statusCode?, headers?
 *     }]
 *   }
 *
 * Auth: admin role wajib. Hapus endpoint ini setelah debug push selesai.
 */
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { normalizePemKey } from "@/lib/pem-utils";

export const dynamic = "force-dynamic";
export const maxDuration = 30;

function hint(token: string): string {
  if (token.length <= 16) return token;
  return `${token.slice(0, 12)}…${token.slice(-6)}`;
}

export async function POST(req: NextRequest) {
  try {
    const csrfReject = assertSameOrigin(req);
    if (csrfReject) return csrfReject;

    const session = await getSession("ADMIN");
    if (!session || session.role !== "ADMIN") {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const json = await req.json().catch(() => ({}));
    const targetUserId =
      typeof json?.userId === "string" ? json.userId.trim() : null;
    if (!targetUserId) {
      return NextResponse.json(
        { error: "Body harus include { userId: '...' }" },
        { status: 400 },
      );
    }

    const title =
      typeof json?.title === "string" && json.title.trim()
        ? json.title.trim()
        : "🔔 Direct APNs Test";
    const body =
      typeof json?.body === "string" && json.body.trim()
        ? json.body.trim()
        : "Bypass Firebase — direct from backend Natalo ke Apple APNs.";

    // ── 1. Verify env ──────────────────────────────────────────────
    const keyId = process.env.APNS_KEY_ID?.trim();
    const teamId = process.env.APNS_TEAM_ID?.trim();
    const rawKeyContent = process.env.APNS_KEY_CONTENT;
    const bundleId = process.env.APNS_BUNDLE_ID || "com.natalo.petshop";
    const production = process.env.APNS_PRODUCTION === "true";

    if (!keyId || !teamId || !rawKeyContent) {
      return NextResponse.json(
        {
          error:
            "APNS_KEY_ID / APNS_TEAM_ID / APNS_KEY_CONTENT belum di-set di Vercel env.",
          envState: {
            APNS_KEY_ID: Boolean(keyId),
            APNS_TEAM_ID: Boolean(teamId),
            APNS_KEY_CONTENT: Boolean(rawKeyContent),
            APNS_BUNDLE_ID: bundleId,
            APNS_PRODUCTION: production,
          },
        },
        { status: 500 },
      );
    }

    // ── 2. Fetch APNs tokens from DB ──────────────────────────────
    const subs = await prisma.pushSubscription.findMany({
      where: {
        userId: targetUserId,
        endpoint: { startsWith: "apns:" },
      },
      orderBy: { createdAt: "desc" },
    });

    if (subs.length === 0) {
      return NextResponse.json({
        ok: true,
        targetUserId,
        apnsTokensFound: 0,
        hint:
          "User belum punya APNs subscription. Setelah Flutter app baru di-install + login, push_notification_service akan register APNs token ke /api/push/subscribe-apns. Cek juga apakah user sudah login customer di app.",
      });
    }

    // ── 3. Init APNs provider ──────────────────────────────────────
    const keyContent = normalizePemKey(rawKeyContent);

    const apn = await import("@parse/node-apn");
    const provider = new apn.Provider({
      token: { key: Buffer.from(keyContent, "utf-8"), keyId, teamId },
      production,
    });

    // ── 4. Send to each token ──────────────────────────────────────
    type Result = {
      tokenHint: string;
      status: "ok" | "error";
      sentCount?: number;
      reason?: string;
      statusCode?: number | string;
      tokenCreatedAt?: string;
      apnsTopicSent: string;
      raw?: unknown;
    };

    const results: Result[] = [];

    await Promise.all(
      subs.map(async (sub) => {
        const token = sub.endpoint.replace(/^apns:/, "");
        const note = new apn.Notification();
        note.alert = { title, body };
        note.sound = "default";
        note.topic = bundleId;
        note.priority = 10;
        note.pushType = "alert";
        note.badge = 1;
        note.payload = { source: "apns-direct-test" };

        try {
          const result = await provider.send(note, token);
          if (result.sent.length > 0) {
            results.push({
              tokenHint: hint(token),
              status: "ok",
              sentCount: result.sent.length,
              apnsTopicSent: bundleId,
              tokenCreatedAt: sub.createdAt.toISOString(),
            });
          } else if (result.failed.length > 0) {
            const f = result.failed[0];
            results.push({
              tokenHint: hint(token),
              status: "error",
              reason:
                f.response?.reason ??
                (f as { error?: string }).error ??
                "unknown",
              statusCode: f.status,
              apnsTopicSent: bundleId,
              tokenCreatedAt: sub.createdAt.toISOString(),
              raw: f,
            });
          } else {
            results.push({
              tokenHint: hint(token),
              status: "error",
              reason: "no response from APNs",
              apnsTopicSent: bundleId,
              tokenCreatedAt: sub.createdAt.toISOString(),
            });
          }
        } catch (err) {
          results.push({
            tokenHint: hint(token),
            status: "error",
            reason: err instanceof Error ? err.message : String(err),
            apnsTopicSent: bundleId,
            tokenCreatedAt: sub.createdAt.toISOString(),
          });
        }
      }),
    );

    provider.shutdown();

    return NextResponse.json({
      ok: true,
      adminUserId: session.sub,
      targetUserId,
      apnsTokensFound: subs.length,
      envConfig: {
        keyId,
        teamId,
        bundleId,
        production,
        apnsHost: production
          ? "api.push.apple.com"
          : "api.sandbox.push.apple.com",
      },
      results,
      hint:
        "Reason `BadDeviceToken` = token salah / device tidak ada. " +
        "`InvalidProviderToken` = JWT signature wrong (key issue). " +
        "`DeviceTokenNotForTopic` = bundle ID mismatch. " +
        "`TopicDisallowed` = bundle ID tidak punya push capability. " +
        "Status `ok` = APNs accept, device harus terima notif.",
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal error";
    return NextResponse.json(
      { error: `APNs direct test gagal: ${message}` },
      { status: 500 },
    );
  }
}
