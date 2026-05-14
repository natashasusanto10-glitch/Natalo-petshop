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
// Promise yang resolve ke provider — di-set sekali saat init dimulai, lalu
// di-await oleh semua caller berikutnya. Mencegah race condition di mana
// concurrent broadcast (2+ user paralel) ada yang baca `apnInitialized=true`
// tapi `apnProvider` masih null (init belum selesai), yang bikin push gagal
// dengan "skip-no-provider" walau env vars valid.
let apnProviderInitPromise: Promise<import("@parse/node-apn").Provider | null> | null = null;

async function getApnProvider() {
  if (apnProviderInitPromise) return apnProviderInitPromise;
  apnProviderInitPromise = initApnProviderInternal();
  return apnProviderInitPromise;
}

async function initApnProviderInternal(): Promise<
  import("@parse/node-apn").Provider | null
> {

  // Trim whitespace dari env values — pas paste di Vercel kadang ada
  // tab/space tersangkut di awal/akhir yang bikin JWT sign fail dengan
  // "secretOrPrivateKey must be an asymmetric key when using ES256".
  const keyId = process.env.APNS_KEY_ID?.trim();
  const teamId = process.env.APNS_TEAM_ID?.trim();
  const rawKeyContent = process.env.APNS_KEY_CONTENT;
  const production = process.env.APNS_PRODUCTION === "true";

  if (!keyId || !teamId || !rawKeyContent) {
    // APNs belum di-config — silently skip. Web Push tetap kerja.
    return null;
  }

  // Normalize PEM content — handle 3 common paste failures di hosting:
  //   1. "\n" escape literal (2 chars) — Vercel/Heroku kadang strip newlines
  //   2. Single-line concat tanpa newline sama sekali
  //   3. Whitespace berlebih di start/end
  // PEM parser di @parse/node-apn / jsonwebtoken butuh actual LF newlines
  // antara BEGIN marker, base64 content (max 64 chars/line), END marker.
  let keyContent = rawKeyContent.replace(/\\n/g, "\n").trim();

  // Auto-fix single-line PEM: kalau BEGIN/END present tapi cuma 1 baris,
  // extract base64 body lalu split per 64 chars (RFC 7468 PEM format).
  // Defense untuk hosting yang strip newlines saat paste env value.
  if (
    keyContent.includes("-----BEGIN PRIVATE KEY-----") &&
    keyContent.includes("-----END PRIVATE KEY-----") &&
    !keyContent.includes("\n")
  ) {
    const body = keyContent
      .replace("-----BEGIN PRIVATE KEY-----", "")
      .replace("-----END PRIVATE KEY-----", "")
      .replace(/\s/g, "");
    const wrappedBody = (body.match(/.{1,64}/g) ?? []).join("\n");
    keyContent =
      "-----BEGIN PRIVATE KEY-----\n" +
      wrappedBody +
      "\n-----END PRIVATE KEY-----";
  }

  // Sanity check PEM markers — kalau hilang, env value rusak.
  if (
    !keyContent.includes("-----BEGIN PRIVATE KEY-----") ||
    !keyContent.includes("-----END PRIVATE KEY-----")
  ) {
    console.error(
      "[apns] APNS_KEY_CONTENT missing PEM headers — check env var format",
    );
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
    console.error(
      "[apns] provider init failed:",
      err instanceof Error ? err.message : String(err),
    );
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
  if (!provider) return;

  const bundleId = process.env.APNS_BUNDLE_ID || "com.natalo.petshop";

  const subs = await prisma.pushSubscription
    .findMany({
      where: { userId, endpoint: { startsWith: "apns:" } },
    })
    .catch(() => []);

  if (subs.length === 0) return;

  const apn = await import("@parse/node-apn");

  const results = await Promise.all(
    subs.map(async (sub) => {
      const token = sub.endpoint.replace(/^apns:/, "");
      const note = new apn.Notification();
      // Visible notification (banner + sound + lockscreen) di iPhone.
      // PENTING: jangan set contentAvailable=true — itu signal Apple
      // sebagai BACKGROUND push (silent, no banner). Untuk visible
      // alert pakai pushType="alert" + priority=10 (iOS 13+ wajib).
      note.alert = { title: payload.title, body: payload.body };
      note.sound = "default";
      note.topic = bundleId;
      note.priority = 10;
      note.pushType = "alert";
      note.badge = 1;
      note.payload = {
        ...(payload.data ?? {}),
        url: payload.url,
      };

      try {
        const result = await provider.send(note, token);
        if (result.failed?.length) {
          console.error(
            "[apns] send failed",
            result.failed.map((f) => ({
              status: f.status,
              reason: f.response?.reason ?? null,
            })),
          );
        }
        return { sub, result };
      } catch (err) {
        console.error(
          "[apns] send threw",
          err instanceof Error ? err.message : String(err),
        );
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
    apnProviderInitPromise = null;
  }
}
