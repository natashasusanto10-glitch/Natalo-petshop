import { prisma } from "./prisma";
import { normalizePemKey } from "./pem-utils";

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
 * PENTING: fungsi ini SENGAJA TIDAK dipanggil dari fungsi notifikasi
 * "real" manapun (sendOrderStatusPush, sendFeedPublishPush, dll) — semua
 * itu kini hanya panggil sendPushToUser() (web) + sendFcmToUser()
 * (Android+iOS, Firebase forward ke APNs Apple di baliknya). Client
 * Flutter iOS register token FCM DAN raw APNs sekaligus untuk device yang
 * sama ("diagnostic backup channel" — lihat push_notification_service.dart);
 * memanggil sendApnsToUser() bersamaan sendFcmToUser() mengirim 2
 * notifikasi native identik ke 1 perangkat. Fungsi ini masih ada untuk
 * dipanggil manual/diagnostic saja (bukan dari dispatch path produksi).
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

  // Normalize PEM content — handle multi-line, literal `\n`, dan
  // single-line tanpa newline (yang sering ke-paste salah di Vercel
  // dashboard). Lihat lib/pem-utils.ts.
  const keyContent = normalizePemKey(rawKeyContent);

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
  /** Rich content — image URL untuk attachment di notification banner.
   *  Wajib HTTPS, format JPEG/PNG/GIF/MP4 (max 10 MB).
   *  Butuh Notification Service Extension (NSE) di iOS app target untuk
   *  fetch + attach image. Tanpa NSE, image diabaikan — text-only notif
   *  tetap di-deliver.
   *  Sinkron dengan PushPayload.imageUrl di lib/push.ts — caller pass
   *  field yang sama, sendApnsToUser baca via imageUrl. */
  imageUrl?: string | null;
  /** Notification category — match dengan UNNotificationCategory yang
   *  di-register di AppDelegate. Memunculkan action buttons (Approve/
   *  Reject untuk admin moderation, dll). */
  category?: string | null;
};

/**
 * Send APNs push ke semua iOS device tokens user ini.
 * Token disimpan di PushSubscription dengan endpoint "apns:<token>".
 */
export async function sendApnsToUser(userId: string, payload: ApnsPayload) {
  const provider = await getApnProvider();
  if (!provider) {
    console.warn("[apns] skip: provider null (env vars missing/invalid)", {
      userId,
    });
    return;
  }

  const bundleId = process.env.APNS_BUNDLE_ID || "com.natalo.petshop";

  const subs = await prisma.pushSubscription
    .findMany({
      where: { userId, endpoint: { startsWith: "apns:" } },
    })
    .catch(() => []);

  if (subs.length === 0) {
    console.warn("[apns] skip: no apns subscriptions for user", { userId });
    return;
  }

  console.log("[apns] sending", { userId, tokenCount: subs.length });

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
      // mutableContent=true → iOS akan deliver notification ke Notification
      // Service Extension dulu sebelum tampil. NSE bisa modify body, add
      // attachment (image preview), localize, dll. Tanpa NSE, flag ini
      // tidak ada efek (text-only notif tetap tampil normal).
      if (payload.imageUrl) {
        note.mutableContent = true;
      }
      // category → match dengan UNNotificationCategory yang di-register
      // di AppDelegate (lihat ios/App/App/AppDelegate.swift). Trigger
      // action buttons (e.g., "Approve" / "Reject" untuk admin moderation).
      if (payload.category) {
        // @parse/node-apn Notification type tidak include `category`
        // property di TS defs, tapi runtime field di-honor — maps ke
        // aps.category. Pakai type assertion untuk bypass TS check.
        (note as unknown as { category: string }).category = payload.category;
      }
      note.payload = {
        ...(payload.data ?? {}),
        url: payload.url,
        // NSE di iOS app baca `attachment-url` dari custom payload,
        // fetch image, lalu attach ke notif sebagai preview.
        ...(payload.imageUrl
          ? { "attachment-url": payload.imageUrl }
          : {}),
      };

      try {
        const result = await provider.send(note, token);
        const tokenHint = `${token.slice(0, 8)}…${token.slice(-6)}`;
        if (result.failed?.length) {
          console.error(
            "[apns] send failed",
            result.failed.map((f) => ({
              tokenHint,
              status: f.status,
              reason: f.response?.reason ?? null,
            })),
          );
        }
        if (result.sent?.length) {
          // Log success dengan info lengkap untuk debug "APNs accept tapi
          // tidak deliver ke device". Kalau muncul tapi notif tidak sampai
          // HP: cek (a) Focus / DND iOS, (b) bundle ID match topic,
          // (c) production env match build type (TestFlight=production,
          // Xcode debug=sandbox), (d) iOS Settings → app → Notifications enabled.
          console.log("[apns] send accepted by APNs", {
            tokenHint,
            topic: bundleId,
            production: process.env.APNS_PRODUCTION === "true",
            pushType: note.pushType,
            sentCount: result.sent.length,
          });
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
