import { prisma } from "./prisma";

/**
 * FCM (Firebase Cloud Messaging) sender — kirim push ke Android native app
 * (.apk via Play Store) lewat @capacitor/push-notifications.
 *
 * Setup yang dibutuhkan via env variables (dari Firebase Service Account JSON
 * yang di-download dari Firebase Console → Project Settings → Service accounts
 * → Generate new private key):
 * - FCM_PROJECT_ID       : "project_id" di JSON
 * - FCM_CLIENT_EMAIL     : "client_email" di JSON
 * - FCM_PRIVATE_KEY      : "private_key" di JSON (full PEM, multi-line)
 *                          Tip: simpan di Vercel/.env.local sebagai single
 *                          line dengan literal "\n" — kita decode di bawah.
 *
 * Token format: PushSubscription.endpoint = "fcm:<DEVICE_TOKEN>"
 *
 * Plays well dengan existing webpush + APNs — sendOrderStatusPush() panggil
 * sendPushToUser() (web), sendApnsToUser() (iOS), DAN sendFcmToUser()
 * (Android), masing-masing target subset subs berdasarkan endpoint prefix.
 */

let fcmApp: import("firebase-admin/app").App | null = null;
let fcmInitialized = false;

async function getFcmMessaging() {
  if (fcmInitialized) {
    if (!fcmApp) return null;
    const { getMessaging } = await import("firebase-admin/messaging");
    return getMessaging(fcmApp);
  }
  fcmInitialized = true;

  const projectId = process.env.FCM_PROJECT_ID;
  const clientEmail = process.env.FCM_CLIENT_EMAIL;
  const rawPrivateKey = process.env.FCM_PRIVATE_KEY;

  if (!projectId || !clientEmail || !rawPrivateKey) {
    // FCM belum di-config — silently skip. Web Push & APNs tetap kerja.
    return null;
  }

  // Vercel env vars sering disimpan dengan "\n" literal (bukan newline asli).
  const privateKey = rawPrivateKey.replace(/\\n/g, "\n");

  try {
    const { initializeApp, getApps, cert } = await import("firebase-admin/app");
    const existing = getApps().find((a) => a.name === "natalo-fcm");
    fcmApp =
      existing ??
      initializeApp(
        {
          credential: cert({ projectId, clientEmail, privateKey }),
        },
        "natalo-fcm",
      );
    const { getMessaging } = await import("firebase-admin/messaging");
    return getMessaging(fcmApp);
  } catch (err) {
    console.warn("FCM init failed:", err);
    fcmApp = null;
    return null;
  }
}

export type FcmPayload = {
  title: string;
  body: string;
  url?: string;
  /** Group key — Android notification dgn tag sama akan replace existing */
  tag?: string;
  /** Custom data dilewatkan ke app (string-only di FCM data payload) */
  data?: Record<string, string>;
};

/**
 * Send FCM push ke semua Android device tokens user ini.
 * Token disimpan di PushSubscription dengan endpoint "fcm:<token>".
 *
 * Pakai `sendEachForMulticast` (bukan `sendMulticast` yang deprecated) — kirim
 * paralel ke banyak token sekaligus, hasilnya per-token jadi kita bisa
 * cleanup invalid tokens.
 */
export async function sendFcmToUser(userId: string, payload: FcmPayload) {
  const messaging = await getFcmMessaging();
  if (!messaging) return;

  const subs = await prisma.pushSubscription
    .findMany({
      where: { userId, endpoint: { startsWith: "fcm:" } },
    })
    .catch(() => []);

  if (subs.length === 0) return;

  const tokens = subs.map((s) => s.endpoint.replace(/^fcm:/, ""));

  // FCM data payload: semua value harus string. Kita pakai data-only message
  // (bukan notification) supaya Android app bisa custom-render via plugin's
  // pushNotificationReceived listener. Plugin handle native notification
  // display saat app di background — payload `data` di-forward ke listener.
  //
  // Untuk konsistensi dengan web push (yang punya title/body terlihat saat
  // app killed), kita kirim BOTH notification + data:
  // - `notification` → ditampilkan native saat app background/killed
  // - `data` → di-forward ke app saat foreground untuk in-app handling
  const dataPayload: Record<string, string> = {
    title: payload.title,
    body: payload.body,
    ...(payload.url ? { url: payload.url } : {}),
    ...(payload.tag ? { tag: payload.tag } : {}),
    ...(payload.data ?? {}),
  };

  try {
    const res = await messaging.sendEachForMulticast({
      tokens,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: dataPayload,
      android: {
        priority: "high",
        notification: {
          tag: payload.tag,
          // Click action akan trigger plugin's pushNotificationActionPerformed
          // listener; app handle navigation ke `data.url` sendiri.
          clickAction: "FCM_PLUGIN_ACTIVITY",
        },
      },
    });

    // Cleanup invalid tokens (UNREGISTERED, INVALID_ARGUMENT, etc).
    if (res.failureCount > 0) {
      await Promise.all(
        res.responses.map(async (r, idx) => {
          if (r.success) return;
          const code = r.error?.code;
          // Errors yang berarti token sudah tidak valid lagi → hapus dari DB.
          // Codes dari firebase-admin/messaging:
          // - messaging/registration-token-not-registered
          // - messaging/invalid-registration-token
          // - messaging/invalid-argument
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token" ||
            code === "messaging/invalid-argument"
          ) {
            await prisma.pushSubscription
              .delete({ where: { id: subs[idx].id } })
              .catch(() => {});
          }
        }),
      );
    }
  } catch (err) {
    console.warn("FCM send failed:", err);
  }
}
