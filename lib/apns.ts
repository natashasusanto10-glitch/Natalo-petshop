import { prisma } from "./prisma";

/**
 * APNs (Apple Push Notification Service) sender — kirim push ke iOS native
 * app (.ipa di TestFlight / App Store).
 *
 * Setup yang dibutuhkan via env variables:
 * - APNS_KEY_ID         : 10-char Key ID dari .p8 file
 * - APNS_TEAM_ID        : Apple Developer Team ID (87FXPV558A)
 * - APNS_KEY_CONTENT    : isi file .p8 (BEGIN PRIVATE KEY...END PRIVATE KEY)
 * - APNS_BUNDLE_ID      : com.natalo.petshop
 * - APNS_PRODUCTION     : "true" untuk production APNs, "false" untuk sandbox
 *
 * Token format: PushSubscription.endpoint = "apns:<HEX_TOKEN>"
 *
 * Plays well dengan existing webpush flow — sendOrderStatusPush() bisa
 * panggil BOTH sendPushToUser() (web) DAN sendApnsToUser() (iOS native),
 * masing-masing target subset subs.
 */

let apnProvider: import("@parse/node-apn").Provider | null = null;
let apnInitialized = false;

async function getApnProvider() {
  if (apnInitialized) return apnProvider;
  apnInitialized = true;

  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const keyContent = process.env.APNS_KEY_CONTENT;
  const production = process.env.APNS_PRODUCTION === "true";

  if (!keyId || !teamId || !keyContent) {
    // APNs belum di-config — silently skip. Web Push tetap kerja.
    return null;
  }

  try {
    const apn = await import("@parse/node-apn");
    apnProvider = new apn.Provider({
      token: { key: Buffer.from(keyContent, "utf-8"), keyId, teamId },
      production,
    });
    return apnProvider;
  } catch (err) {
    console.warn("APNs provider init failed:", err);
    return null;
  }
}

export type ApnsPayload = {
  title: string;
  body: string;
  url?: string;
  /** Custom data dilewatkan ke app via aps.payload */
  data?: Record<string, unknown>;
};

/**
 * Send APNs push ke semua iOS device tokens user ini.
 * Token disimpan di PushSubscription dengan endpoint "apns:<token>".
 */
export async function sendApnsToUser(userId: string, payload: ApnsPayload) {
  const provider = await getApnProvider();
  if (!provider) {
    console.log("[apns]", JSON.stringify({
      event: "skip-no-provider",
      reason: "APNs env vars belum lengkap atau init gagal",
      userId: userId.slice(-6),
    }));
    return;
  }

  const bundleId = process.env.APNS_BUNDLE_ID || "com.natalo.petshop";
  const production = process.env.APNS_PRODUCTION === "true";

  const subs = await prisma.pushSubscription
    .findMany({
      where: { userId, endpoint: { startsWith: "apns:" } },
    })
    .catch(() => []);

  console.log("[apns]", JSON.stringify({
    event: "sending",
    userId: userId.slice(-6),
    apnsTokensFound: subs.length,
    bundleId,
    production,
  }));

  if (subs.length === 0) {
    console.log("[apns]", JSON.stringify({
      event: "skip-no-tokens",
      userId: userId.slice(-6),
    }));
    return;
  }

  const apn = await import("@parse/node-apn");

  const results = await Promise.all(
    subs.map(async (sub) => {
      const token = sub.endpoint.replace(/^apns:/, "");
      const note = new apn.Notification();
      note.alert = { title: payload.title, body: payload.body };
      note.sound = "default";
      note.topic = bundleId;
      note.payload = {
        ...(payload.data ?? {}),
        url: payload.url,
      };
      note.contentAvailable = true;

      try {
        const result = await provider.send(note, token);
        console.log("[apns]", JSON.stringify({
          event: "send-result",
          userId: userId.slice(-6),
          tokenPreview: token.slice(0, 12) + "...",
          sent: result.sent?.length ?? 0,
          failed: result.failed?.length ?? 0,
          failedReasons: result.failed?.map((f) => ({
            status: f.status,
            reason: f.response?.reason ?? null,
            errorCode: f.response?.["timestamp"] ?? null,
          })) ?? [],
        }));
        return { sub, result };
      } catch (err) {
        console.error("[apns]", JSON.stringify({
          event: "send-throw",
          userId: userId.slice(-6),
          tokenPreview: token.slice(0, 12) + "...",
          error: err instanceof Error ? err.message : String(err),
        }));
        return { sub, error: err };
      }
    }),
  );

  // Cleanup token yang invalid (BadDeviceToken / Unregistered)
  for (const r of results) {
    if (r.result?.failed?.length) {
      for (const f of r.result.failed) {
        const reason = f.response?.reason;
        if (reason === "BadDeviceToken" || reason === "Unregistered") {
          await prisma.pushSubscription
            .delete({ where: { id: r.sub.id } })
            .catch(() => {});
        }
      }
    }
  }
}

/**
 * Cleanup APNs provider connection saat shutdown (dev).
 * Production serverless gak perlu — function ephemeral.
 */
export function shutdownApns() {
  if (apnProvider) {
    apnProvider.shutdown();
    apnProvider = null;
    apnInitialized = false;
  }
}
