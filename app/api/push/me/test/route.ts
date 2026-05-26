/**
 * POST /api/push/me/test
 *
 * Diagnostic-only: customer trigger test push ke device-nya sendiri.
 * Lebih targeted daripada admin broadcast — return result mentah per
 * token (sent/failed + reason). Berguna untuk debug "APNs accept tapi
 * notif tidak sampai HP".
 *
 * Body: { title?: string, body?: string }
 * Response: {
 *   ok,
 *   subscriptionCount: { web, apns, fcm, total },
 *   results: {
 *     web:  [{ endpointHint, status, statusCode?, error? }],
 *     apns: [{ tokenHint, status, sentCount?, reason?, statusCode? }],
 *     fcm:  [{ tokenHint, status, errorCode?, errorMsg? }],
 *   }
 * }
 */
import { NextRequest, NextResponse } from "next/server";
import webpush from "web-push";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { normalizePemKey } from "@/lib/pem-utils";

const DEFAULT_TITLE = "🔔 Test Push";
const DEFAULT_BODY = "Kalau notif ini muncul, push channel kamu aktif.";

function hint(str: string): string {
  if (str.length <= 24) return str.slice(0, 16);
  return `${str.slice(0, 12)}…${str.slice(-6)}`;
}

export async function POST(req: NextRequest) {
  const session = await getSession("CUSTOMER");
  if (!session || session.role !== "CUSTOMER") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const userId = session.sub;
  const json = await req.json().catch(() => ({}));
  const title =
    typeof json?.title === "string" && json.title.trim()
      ? json.title.trim()
      : DEFAULT_TITLE;
  const body =
    typeof json?.body === "string" && json.body.trim()
      ? json.body.trim()
      : DEFAULT_BODY;

  const subs = await prisma.pushSubscription.findMany({
    where: { userId },
    orderBy: { createdAt: "desc" },
  });
  const webSubs = subs.filter((s) => s.endpoint.startsWith("https://"));
  const apnsSubs = subs.filter((s) => s.endpoint.startsWith("apns:"));
  const fcmSubs = subs.filter((s) => s.endpoint.startsWith("fcm:"));

  type WebResult = {
    endpointHint: string;
    status: "ok" | "error";
    statusCode?: number;
    error?: string;
  };
  type ApnsResult = {
    tokenHint: string;
    status: "ok" | "error";
    sentCount?: number;
    reason?: string;
    statusCode?: number;
    createdAt?: string;
  };
  type FcmResult = {
    tokenHint: string;
    status: "ok" | "error";
    errorCode?: string;
    errorMsg?: string;
  };

  const results: { web: WebResult[]; apns: ApnsResult[]; fcm: FcmResult[] } = {
    web: [],
    apns: [],
    fcm: [],
  };

  const payload = { title, body, url: "/akun/notifikasi" };
  const payloadStr = JSON.stringify(payload);

  // ── Web Push ─────────────────────────────────────────────
  if (webSubs.length > 0) {
    const vapidPublic = process.env.VAPID_PUBLIC_KEY;
    const vapidPrivate = process.env.VAPID_PRIVATE_KEY;
    if (!vapidPublic || !vapidPrivate) {
      results.web.push({
        endpointHint: "—",
        status: "error",
        error: "VAPID keys tidak ter-set di env.",
      });
    } else {
      webpush.setVapidDetails("mailto:admin@toko.com", vapidPublic, vapidPrivate);
      await Promise.all(
        webSubs.map(async (sub) => {
          try {
            await webpush.sendNotification(
              {
                endpoint: sub.endpoint,
                keys: { p256dh: sub.p256dh, auth: sub.auth },
              },
              payloadStr,
            );
            results.web.push({ endpointHint: hint(sub.endpoint), status: "ok" });
          } catch (err: unknown) {
            const obj =
              err && typeof err === "object"
                ? (err as Record<string, unknown>)
                : {};
            results.web.push({
              endpointHint: hint(sub.endpoint),
              status: "error",
              statusCode:
                typeof obj.statusCode === "number" ? obj.statusCode : undefined,
              error: err instanceof Error ? err.message : String(err),
            });
          }
        }),
      );
    }
  }

  // ── APNs ─────────────────────────────────────────────────
  if (apnsSubs.length > 0) {
    const keyId = process.env.APNS_KEY_ID?.trim();
    const teamId = process.env.APNS_TEAM_ID?.trim();
    const rawKeyContent = process.env.APNS_KEY_CONTENT;
    const bundleId = process.env.APNS_BUNDLE_ID || "com.natalo.petshop";
    const production = process.env.APNS_PRODUCTION === "true";

    if (!keyId || !teamId || !rawKeyContent) {
      results.apns.push({
        tokenHint: "—",
        status: "error",
        reason: "APNS env tidak lengkap.",
      });
    } else {
      const keyContent = normalizePemKey(rawKeyContent);

      try {
        const apn = await import("@parse/node-apn");
        const provider = new apn.Provider({
          token: { key: Buffer.from(keyContent, "utf-8"), keyId, teamId },
          production,
        });

        await Promise.all(
          apnsSubs.map(async (sub) => {
            const token = sub.endpoint.replace(/^apns:/, "");
            const note = new apn.Notification();
            note.alert = { title, body };
            note.sound = "default";
            note.topic = bundleId;
            note.priority = 10;
            note.pushType = "alert";
            note.badge = 1;
            note.payload = { url: "/akun/notifikasi" };

            try {
              const result = await provider.send(note, token);
              if (result.sent.length > 0) {
                results.apns.push({
                  tokenHint: hint(token),
                  status: "ok",
                  sentCount: result.sent.length,
                  createdAt: sub.createdAt.toISOString(),
                });
              } else if (result.failed.length > 0) {
                const f = result.failed[0];
                results.apns.push({
                  tokenHint: hint(token),
                  status: "error",
                  reason:
                    f.response?.reason ??
                    (f as { error?: string }).error ??
                    "unknown",
                  statusCode: f.status as unknown as number | undefined,
                  createdAt: sub.createdAt.toISOString(),
                });
              } else {
                results.apns.push({
                  tokenHint: hint(token),
                  status: "error",
                  reason: "no response",
                  createdAt: sub.createdAt.toISOString(),
                });
              }
            } catch (err) {
              results.apns.push({
                tokenHint: hint(token),
                status: "error",
                reason: err instanceof Error ? err.message : String(err),
                createdAt: sub.createdAt.toISOString(),
              });
            }
          }),
        );

        provider.shutdown();
      } catch (err) {
        results.apns.push({
          tokenHint: "—",
          status: "error",
          reason: `Init APNs gagal: ${
            err instanceof Error ? err.message : String(err)
          }`,
        });
      }
    }
  }

  // ── FCM Native (untuk Android) ───────────────────────────
  if (fcmSubs.length > 0) {
    const projectId = process.env.FCM_PROJECT_ID;
    const clientEmail = process.env.FCM_CLIENT_EMAIL;
    const rawPrivateKey = process.env.FCM_PRIVATE_KEY;

    if (!projectId || !clientEmail || !rawPrivateKey) {
      results.fcm.push({
        tokenHint: "—",
        status: "error",
        errorMsg: "FCM env tidak lengkap.",
      });
    } else {
      try {
        const { initializeApp, getApps, cert, deleteApp } = await import(
          "firebase-admin/app"
        );
        const { getMessaging } = await import("firebase-admin/messaging");
        const privateKey = normalizePemKey(rawPrivateKey);
        const appName = `fcm-me-test-${Date.now()}`;
        const existing = getApps().find((a) => a.name === appName);
        const app =
          existing ??
          initializeApp(
            { credential: cert({ projectId, clientEmail, privateKey }) },
            appName,
          );
        const messaging = getMessaging(app);

        const tokens = fcmSubs.map((s) => s.endpoint.replace(/^fcm:/, ""));
        const resp = await messaging.sendEachForMulticast({
          tokens,
          notification: { title, body },
          data: { url: "/akun/notifikasi" },
        });

        for (let i = 0; i < tokens.length; i++) {
          const r = resp.responses[i];
          if (r.success) {
            results.fcm.push({ tokenHint: hint(tokens[i]), status: "ok" });
          } else {
            results.fcm.push({
              tokenHint: hint(tokens[i]),
              status: "error",
              errorCode: r.error?.code,
              errorMsg: r.error?.message,
            });
          }
        }
        await deleteApp(app).catch(() => {});
      } catch (err) {
        results.fcm.push({
          tokenHint: "—",
          status: "error",
          errorMsg: `Init FCM gagal: ${
            err instanceof Error ? err.message : String(err)
          }`,
        });
      }
    }
  }

  return NextResponse.json({
    ok: true,
    userId,
    subscriptionCount: {
      web: webSubs.length,
      apns: apnsSubs.length,
      fcm: fcmSubs.length,
      total: subs.length,
    },
    results,
    hint:
      subs.length === 0
        ? "Kamu belum punya subscription apapun. Pastikan sudah grant permission push di iOS Settings → Natalo Petshop → Notifications."
        : "Test push terkirim. Lihat HP — kalau tidak muncul, baca field 'reason'/'error' di results. Tokens diurut createdAt desc — yang paling atas = paling baru.",
  });
}
