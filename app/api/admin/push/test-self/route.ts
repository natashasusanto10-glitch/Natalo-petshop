/**
 * POST /api/admin/push/test-self
 *
 * Diagnostic-only: kirim test push ke semua subscription yang link ke
 * admin yang sedang login. Berguna untuk debug "kenapa push gak nyampe HP".
 *
 * Beda dari "Test ke saya" di broadcast: endpoint ini TIDAK pakai
 * sendApnsToUser/sendFcmToUser yang swallow error — kita kirim langsung dan
 * surface error mentah dari APNs/FCM/web push server per device.
 *
 * Body (semua optional):
 *   { title?: string, body?: string }
 *
 * Response:
 *   {
 *     ok,
 *     adminUserId,
 *     subscriptionCount: { web, apns, fcm, total },
 *     results: {
 *       web:  [{ endpointHint, status: "ok" | error, error?, statusCode? }],
 *       apns: [{ tokenHint, status: "ok" | error, reason?, statusCode? }],
 *       fcm:  [{ tokenHint, status: "ok" | error, errorCode?, errorMsg? }],
 *     }
 *   }
 */
import { NextRequest, NextResponse } from "next/server";
import webpush from "web-push";
import { getSession } from "@/lib/auth";
import { assertSameOrigin } from "@/lib/csrf";
import { prisma } from "@/lib/prisma";
import { normalizePemKey } from "@/lib/pem-utils";

const DEFAULT_TITLE = "🔔 Test Push (diagnostic)";
const DEFAULT_BODY = "Kalau notifikasi ini muncul di HP, push channel kamu sudah benar.";

function hint(endpoint: string): string {
  if (endpoint.length <= 16) return endpoint;
  return `${endpoint.slice(0, 8)}…${endpoint.slice(-6)}`;
}

export async function POST(req: NextRequest) {
  try {
    const csrfReject = assertSameOrigin(req);
    if (csrfReject) return csrfReject;

    const session = await getSession("ADMIN");
    if (!session || session.role !== "ADMIN") {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const adminUserId = session.sub;
    const json = await req.json().catch(() => ({}));
    const title = typeof json?.title === "string" && json.title.trim() ? json.title.trim() : DEFAULT_TITLE;
    const body = typeof json?.body === "string" && json.body.trim() ? json.body.trim() : DEFAULT_BODY;

    const subs = await prisma.pushSubscription.findMany({
      where: { userId: adminUserId },
    });

    const webSubs = subs.filter((s) => s.endpoint.startsWith("https://"));
    const apnsSubs = subs.filter((s) => s.endpoint.startsWith("apns:"));
    const fcmSubs = subs.filter((s) => s.endpoint.startsWith("fcm:"));

    const subscriptionCount = {
      web: webSubs.length,
      apns: apnsSubs.length,
      fcm: fcmSubs.length,
      total: subs.length,
    };

    type WebResult = { endpointHint: string; status: "ok" | "error"; error?: string; statusCode?: number };
    type ApnsResult = { tokenHint: string; status: "ok" | "error"; reason?: string; statusCode?: number };
    type FcmResult = { tokenHint: string; status: "ok" | "error"; errorCode?: string; errorMsg?: string };

    const results: { web: WebResult[]; apns: ApnsResult[]; fcm: FcmResult[] } = {
      web: [],
      apns: [],
      fcm: [],
    };

    // Hint awal kalau admin gak punya subs sama sekali — kasus paling sering
    // di TestFlight: opt-in dilakukan saat session admin, jadi subscription
    // tersimpan dgn userId null (anonymous), bukan ke-link ke admin userId.
    const anonymousByChannel = await prisma.pushSubscription.findMany({
      where: { userId: null },
      select: { endpoint: true },
    });
    const anonymousCount = {
      web: anonymousByChannel.filter((s) => s.endpoint.startsWith("https://")).length,
      apns: anonymousByChannel.filter((s) => s.endpoint.startsWith("apns:")).length,
      fcm: anonymousByChannel.filter((s) => s.endpoint.startsWith("fcm:")).length,
    };

    const payload = { title, body, url: "/notifications" };
    const payloadStr = JSON.stringify(payload);

    // ── Web Push ─────────────────────────────────────────────────
    if (webSubs.length > 0) {
      const vapidPublic = process.env.VAPID_PUBLIC_KEY;
      const vapidPrivate = process.env.VAPID_PRIVATE_KEY;
      if (!vapidPublic || !vapidPrivate) {
        results.web.push({
          endpointHint: "—",
          status: "error",
          error: "VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY tidak ter-set di Vercel env.",
        });
      } else {
        webpush.setVapidDetails("mailto:admin@toko.com", vapidPublic, vapidPrivate);
        await Promise.all(
          webSubs.map(async (sub) => {
            try {
              await webpush.sendNotification(
                { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
                payloadStr,
              );
              results.web.push({ endpointHint: hint(sub.endpoint), status: "ok" });
            } catch (err: unknown) {
              const obj = (err && typeof err === "object" ? (err as Record<string, unknown>) : {});
              results.web.push({
                endpointHint: hint(sub.endpoint),
                status: "error",
                statusCode: typeof obj.statusCode === "number" ? obj.statusCode : undefined,
                error: err instanceof Error ? err.message : String(err),
              });
            }
          }),
        );
      }
    }

    // ── APNs ─────────────────────────────────────────────────────
    if (apnsSubs.length > 0) {
      // Trim whitespace — pas paste di Vercel kadang ada tab/space tersangkut.
      const keyId = process.env.APNS_KEY_ID?.trim();
      const teamId = process.env.APNS_TEAM_ID?.trim();
      const rawKeyContent = process.env.APNS_KEY_CONTENT;
      const bundleId = process.env.APNS_BUNDLE_ID || "com.natalo.petshop";
      const production = process.env.APNS_PRODUCTION === "true";

      if (!keyId || !teamId || !rawKeyContent) {
        results.apns.push({
          tokenHint: "—",
          status: "error",
          reason: "APNS_KEY_ID / APNS_TEAM_ID / APNS_KEY_CONTENT tidak lengkap di Vercel env.",
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
              note.payload = { url: "/notifications" };

              try {
                const result = await provider.send(note, token);
                if (result.sent.length > 0) {
                  results.apns.push({ tokenHint: hint(token), status: "ok" });
                } else if (result.failed.length > 0) {
                  const f = result.failed[0];
                  results.apns.push({
                    tokenHint: hint(token),
                    status: "error",
                    reason: f.response?.reason ?? (f as { error?: string }).error ?? "unknown",
                    statusCode: f.status as unknown as number | undefined,
                  });
                } else {
                  results.apns.push({ tokenHint: hint(token), status: "error", reason: "no response" });
                }
              } catch (err) {
                results.apns.push({
                  tokenHint: hint(token),
                  status: "error",
                  reason: err instanceof Error ? err.message : String(err),
                });
              }
            }),
          );

          provider.shutdown();
        } catch (err) {
          results.apns.push({
            tokenHint: "—",
            status: "error",
            reason: `Init APNs gagal: ${err instanceof Error ? err.message : String(err)}`,
          });
        }
      }
    }

    // ── FCM ──────────────────────────────────────────────────────
    if (fcmSubs.length > 0) {
      const projectId = process.env.FCM_PROJECT_ID;
      const clientEmail = process.env.FCM_CLIENT_EMAIL;
      const rawPrivateKey = process.env.FCM_PRIVATE_KEY;

      if (!projectId || !clientEmail || !rawPrivateKey) {
        results.fcm.push({
          tokenHint: "—",
          status: "error",
          errorMsg: "FCM_PROJECT_ID / FCM_CLIENT_EMAIL / FCM_PRIVATE_KEY tidak lengkap di Vercel env.",
        });
      } else {
        try {
          const { initializeApp, getApps, cert, deleteApp } = await import("firebase-admin/app");
          const { getMessaging } = await import("firebase-admin/messaging");
          const privateKey = normalizePemKey(rawPrivateKey);
          const appName = `fcm-test-${Date.now()}`;
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
            data: { url: "/notifications" },
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
            errorMsg: `Init FCM gagal: ${err instanceof Error ? err.message : String(err)}`,
          });
        }
      }
    }

    return NextResponse.json({
      ok: true,
      adminUserId,
      subscriptionCount,
      anonymousCount,
      results,
      hint:
        subscriptionCount.total === 0
          ? `Admin (userId ${adminUserId}) tidak punya subscription. ${
              anonymousCount.apns + anonymousCount.web + anonymousCount.fcm > 0
                ? "Ada subscription anonymous (userId=null) — kemungkinan kamu opt-in saat session admin/belum login customer. Coba: logout, login sebagai customer, opt-in ulang di halaman order detail."
                : "Belum ada satu pun device subscribe push di prod."
            }`
          : "Test push terkirim ke device admin. Lihat HP — kalau tidak muncul, baca field 'reason'/'error' di results.",
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Internal error";
    console.error("[push test-self] crashed:", err);
    return NextResponse.json(
      { error: `Test push gagal: ${message}` },
      { status: 500 },
    );
  }
}
