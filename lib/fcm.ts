import { prisma } from "./prisma";
import { normalizePemKey } from "./pem-utils";
import {
  isPushCategoryEnabled,
  type NotificationCategory,
} from "./notification-preferences";

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
 * FCM juga menangani iOS (Firebase forward token "fcm:..." ke APNs Apple
 * di baliknya) — client Flutter register token FCM di KEDUA platform.
 * sendOrderStatusPush() dkk hanya panggil sendPushToUser() (web) DAN
 * sendFcmToUser() (Android+iOS). sendApnsToUser() (lib/apns.ts, direct
 * APNs) SENGAJA TIDAK dipanggil bersamaan — client iOS juga register raw
 * APNs token sebagai channel diagnostic terpisah; memanggil kedua fungsi
 * sekaligus mengirim 2 notifikasi native identik ke 1 perangkat iOS yang
 * sama (root cause bug "sering double notifikasi").
 */

/** App yang SUDAH berhasil di-init. Hanya sukses yang di-cache — lihat di
 *  bawah kenapa meng-cache kegagalan berbahaya. */
let fcmApp: import("firebase-admin/app").App | null = null;
/** Guard supaya peringatan "env belum di-set" tidak spam tiap kali dipanggil. */
let fcmConfigWarned = false;

/**
 * Baca kredensial FCM dari env. Dipisah jadi fungsi murni supaya bisa dites
 * tanpa menyentuh firebase-admin, dan supaya daftar env yang dibutuhkan punya
 * satu tempat.
 */
export function readFcmConfig(env: Record<string, string | undefined>) {
  return {
    projectId: env.FCM_PROJECT_ID,
    clientEmail: env.FCM_CLIENT_EMAIL,
    rawPrivateKey: env.FCM_PRIVATE_KEY,
  };
}

/**
 * Nama env yang hilang dari config — dipakai untuk pesan log yang menyebut
 * persis mana yang belum di-set, bukan sekadar "FCM tidak aktif".
 */
export function missingFcmConfigKeys(
  env: Record<string, string | undefined>,
): string[] {
  const { projectId, clientEmail, rawPrivateKey } = readFcmConfig(env);
  return [
    !projectId && "FCM_PROJECT_ID",
    !clientEmail && "FCM_CLIENT_EMAIL",
    !rawPrivateKey && "FCM_PRIVATE_KEY",
  ].filter((v): v is string => typeof v === "string");
}

/**
 * SENGAJA hanya meng-cache hasil SUKSES.
 *
 * Dulu ada flag `fcmInitialized` yang di-set true SEBELUM init dicoba, dan
 * saat init gagal `fcmApp` tinggal null — sehingga semua panggilan berikutnya
 * berhenti di `if (!fcmApp) return null` tanpa pernah mencoba lagi. Di
 * serverless efeknya parah: satu instance Vercel yang gagal init sekali (env
 * telat ter-inject, hiccup jaringan saat ambil kredensial) akan DIAM SELAMANYA
 * selama instance itu hidup — `sendFcmToUser` return di baris pertama, tanpa
 * error, tanpa log. Request yang mendarat di instance sehat tetap terkirim,
 * yang mendarat di instance rusak hilang tanpa jejak, lalu "sembuh sendiri"
 * saat instance itu mati. Persis pola bug "push kadang tidak keluar" yang
 * susah dilacak karena tidak meninggalkan jejak apa pun.
 *
 * Dengan hanya cache sukses, instance yang gagal akan mencoba ulang di request
 * berikutnya. Biaya retry murah: baca env + `getApps()` lookup.
 */
async function getFcmMessaging() {
  if (fcmApp) {
    const { getMessaging } = await import("firebase-admin/messaging");
    return getMessaging(fcmApp);
  }

  const { projectId, clientEmail, rawPrivateKey } = readFcmConfig(process.env);

  if (!projectId || !clientEmail || !rawPrivateKey) {
    // FCM belum di-config — skip. Web Push tetap kerja. Dulu ini return null
    // benar-benar senyap, jadi "push native mati total" tidak terlihat sama
    // sekali di log; sekarang minimal sekali per instance ada jejaknya.
    if (!fcmConfigWarned) {
      fcmConfigWarned = true;
      const missing = missingFcmConfigKeys(process.env);
      console.warn(
        `FCM nonaktif — env belum di-set: ${missing.join(", ")}. ` +
          "Push ke Android & iOS TIDAK terkirim.",
      );
    }
    return null;
  }

  // Normalize PEM — handle 3 format input (multi-line, literal \n,
  // single-line tanpa newline). Lihat lib/pem-utils.ts untuk detail.
  // Sebelumnya cuma replace(/\\n/g) yang gagal kalau Vercel dashboard
  // strip newline saat paste → OpenSSL error "DECODER routines::unsupported".
  const privateKey = normalizePemKey(rawPrivateKey);

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
  /** Image URL — Android BigPictureStyle preview di notification tray.
   *  Wajib HTTPS. Format JPEG/PNG. */
  imageUrl?: string | null;
  /** Notification category — diteruskan ke `aps.category` di payload iOS
   *  (Firebase forward FCM → APNs). Match dengan UNNotificationCategory
   *  yang di-register di iOS AppDelegate, trigger action buttons (mis.
   *  "Lihat"/"Tolak" untuk admin moderation). Sebelumnya field ini hanya
   *  jalan lewat sendApnsToUser (direct APNs) — channel itu dihapus (dobel
   *  notif iOS), jadi category WAJIB diteruskan di sini supaya tombol aksi
   *  tidak hilang senyap di iOS. */
  category?: string | null;
  /** Kategori preferensi user — kalau di-set dan user men-disable kategori
   *  itu (atau master switch OFF), push di-skip di server. JANGAN set untuk
   *  notif kritikal (keamanan). Lihat lib/notification-preferences.ts. */
  prefCategory?: NotificationCategory | null;
  /** True kalau notif ini boleh dirender client-side (avatar bulat dsb) di
   *  token yang capable (clientRenderVersion != null). Dipakai bersama
   *  actorAvatarUrl. Lihat buildFcmMulticastMessage. */
  renderClientSide?: boolean;
  /** URL avatar aktor (mis. yang like/comment/follow) — diteruskan ke
   *  data.actor_avatar_url hanya untuk token capable + renderClientSide. */
  actorAvatarUrl?: string | null;
};

/**
 * APNs `apns-collapse-id` — iOS REPLACE notif di tray yang punya collapse-id
 * sama (padanan `android.notification.tag`). Batas keras Apple: 64 byte;
 * lebih dari itu APNs REJECT seluruh push, jadi WAJIB dipotong. Tag kita
 * ASCII (eventType-id-id) → slice per-karakter == per-byte, aman.
 */
export function apnsCollapseId(tag: string): string {
  return tag.slice(0, 64);
}

/**
 * True kalau error dari FCM berarti TOKEN-nya yang sudah mati (app di-uninstall,
 * token di-rotate) — hanya kasus ini yang boleh menghapus baris dari DB.
 *
 * `messaging/invalid-argument` SENGAJA TIDAK termasuk, walau dulu ada di sini.
 * Kode itu berarti PAYLOAD-nya yang ditolak, bukan tokennya — dan payload sama
 * dikirim ke semua token dalam satu multicast. Artinya satu bug bentuk pesan
 * (mis. header APNs melewati batas, field baru salah tipe) akan menghasilkan
 * `invalid-argument` untuk SETIAP token sekaligus, lalu logika cleanup ini
 * menghapus SELURUH token di database — Android dan iOS, semua user. Setelah
 * itu `subs.length === 0` dan push diam selamanya sampai tiap user membuka app
 * dan mendaftar ulang. Kerusakan permanen dari bug yang sebenarnya sementara.
 */
export function isDeadTokenError(code: string | undefined): boolean {
  return (
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token"
  );
}

/**
 * Bangun objek pesan FCM multicast (TANPA `tokens`) — pure & testable.
 *
 * Dua bentuk:
 * - clientRender=true (token capable + payload.renderClientSide): Android
 *   data-only (tanpa `notification`/`android.notification`) supaya app
 *   custom-render (avatar bulat dsb) via plugin listener. iOS TIDAK PERNAH
 *   data-only — tetap kirim `apns.payload.aps.alert` + `mutable-content: 1`
 *   supaya banner tetap tampil.
 * - selainnya: shape lama (notification + android.notification + apns
 *   tanpa alert eksplisit) — behavior existing dipertahankan persis.
 */
export function buildFcmMulticastMessage(
  payload: FcmPayload,
  opts: { clientRender: boolean },
) {
  // FCM data payload: semua value harus string.
  const dataPayload: Record<string, string> = {
    title: payload.title,
    body: payload.body,
    ...(payload.url ? { url: payload.url } : {}),
    ...(payload.tag ? { tag: payload.tag } : {}),
    ...(payload.data ?? {}),
  };

  const clientRender = payload.renderClientSide === true && opts.clientRender;

  // Hanya https:// yang diteruskan — client (Flutter + iOS NSE) fetch URL ini
  // apa adanya lalu decode sebagai gambar; http:// (MITM-able) tak boleh
  // sampai ke parser gambar native (review adversarial PR #267, finding #1).
  if (clientRender && payload.actorAvatarUrl?.startsWith("https://")) {
    dataPayload.actor_avatar_url = payload.actorAvatarUrl;
  }

  if (clientRender) {
    return {
      data: dataPayload,
      android: {
        priority: "high" as const,
      },
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
          ...(payload.tag
            ? { "apns-collapse-id": apnsCollapseId(payload.tag) }
            : {}),
        },
        payload: {
          aps: {
            alert: { title: payload.title, body: payload.body },
            sound: "default",
            badge: 1,
            // iOS tidak pernah data-only — mutable-content selalu 1 supaya
            // Notification Service Extension tetap jalan (fetch avatar dsb).
            "mutable-content": 1,
            ...(payload.category ? { category: payload.category } : {}),
          },
        },
        ...(payload.imageUrl
          ? { fcmOptions: { imageUrl: payload.imageUrl } }
          : {}),
      },
    };
  }

  // Shape LAMA — dipertahankan persis dari sebelum ekstraksi ini.
  return {
    notification: {
      title: payload.title,
      body: payload.body,
      // imageUrl di top-level notification — FCM auto-render sebagai
      // BigPictureStyle di Android saat app background. Required HTTPS.
      ...(payload.imageUrl ? { imageUrl: payload.imageUrl } : {}),
    },
    data: dataPayload,
    android: {
      priority: "high" as const,
      notification: {
        tag: payload.tag,
        // Click action akan trigger plugin's pushNotificationActionPerformed
        // listener; app handle navigation ke `data.url` sendiri.
        clickAction: "FCM_PLUGIN_ACTIVITY",
        // Android-specific big picture URL — duplikat dari notification.
        // imageUrl di atas. Beberapa launcher (Samsung One UI) pakai
        // path ini, lainnya pakai notification.imageUrl.
        ...(payload.imageUrl ? { imageUrl: payload.imageUrl } : {}),
      },
    },
    // iOS via FCM — Firebase forward ke APNs. Tanpa block ini, default
    // payload aps yang FCM generate cuma punya `alert` (banner), TANPA
    // sound + badge + mutable-content. Akibatnya iOS user dapat banner
    // SILENT (no sound), badge counter app icon tidak naik, dan rich
    // image attachment tidak trigger Notification Service Extension.
    apns: {
      headers: {
        // Priority 10 = immediate delivery (vs 5 = throttled).
        // Wajib untuk alert push iOS 13+.
        "apns-priority": "10",
        // pushType "alert" = visible banner (vs "background" = silent).
        // Wajib iOS 13+ untuk visible notification.
        "apns-push-type": "alert",
        ...(payload.tag
          ? { "apns-collapse-id": apnsCollapseId(payload.tag) }
          : {}),
      },
      payload: {
        aps: {
          sound: "default",
          badge: 1,
          // mutable-content=1 → iOS deliver notif ke Notification Service
          // Extension dulu. NSE bisa fetch image + attach sebagai preview
          // di banner. Hanya set kalau ada imageUrl supaya text-only notif
          // tidak overhead extension launch.
          "mutable-content": payload.imageUrl ? 1 : 0,
          // category → trigger action buttons (mis. admin moderation
          // "Lihat"/"Tolak"). Match UNNotificationCategory di AppDelegate.
          ...(payload.category ? { category: payload.category } : {}),
        },
      },
      // fcm_options.image → Firebase iOS SDK NSE auto-fetch image dan
      // attach ke notif. Bundled di pod 'Firebase/Messaging' — tidak
      // butuh extra NSE target di Xcode (Firebase iOS handles it).
      ...(payload.imageUrl
        ? { fcmOptions: { imageUrl: payload.imageUrl } }
        : {}),
    },
  };
}

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

  // Hormati preferensi user — skip channel ini kalau kategori di-mute.
  if (payload.prefCategory) {
    const enabled = await isPushCategoryEnabled(userId, payload.prefCategory);
    if (!enabled) return;
  }

  const subs = await prisma.pushSubscription
    .findMany({
      where: { userId, endpoint: { startsWith: "fcm:" } },
      select: { id: true, endpoint: true, clientRenderVersion: true },
    })
    .catch(() => []);

  if (subs.length === 0) return;

  // Bagi token per-kapabilitas: token yang sudah pernah lapor
  // clientRenderVersion (app versi baru, bisa custom-render avatar dsb)
  // dapat shape data-only; token lama (belum pernah lapor) tetap dapat
  // shape lama (notification block) — lihat buildFcmMulticastMessage.
  const wantsClientRender = payload.renderClientSide === true;
  const capable = wantsClientRender
    ? subs.filter((s) => s.clientRenderVersion != null)
    : [];
  const legacy = wantsClientRender
    ? subs.filter((s) => s.clientRenderVersion == null)
    : subs;
  const groups = [
    { subs: capable, clientRender: true },
    { subs: legacy, clientRender: false },
  ].filter((g) => g.subs.length > 0);

  for (const g of groups) {
    try {
      const res = await messaging.sendEachForMulticast({
        tokens: g.subs.map((s) => s.endpoint.replace(/^fcm:/, "")),
        ...buildFcmMulticastMessage(payload, { clientRender: g.clientRender }),
      });

      // Cleanup token mati (UNREGISTERED / INVALID_REGISTRATION_TOKEN saja).
      if (res.failureCount > 0) {
        await Promise.all(
          res.responses.map(async (r, idx) => {
            if (r.success) return;
            const code = r.error?.code;
            // Hanya error TOKEN yang boleh menghapus baris — lihat
            // isDeadTokenError untuk kenapa invalid-argument dikecualikan.
            if (isDeadTokenError(code)) {
              await prisma.pushSubscription
                .delete({ where: { id: g.subs[idx].id } })
                .catch(() => {});
              return;
            }
            // Error non-token (paling sering: payload ditolak). Jangan sentuh
            // DB — cukup buat terlihat, karena kalau ini kena semua token
            // artinya push native mati total dan penyebabnya ada di sini.
            console.warn(
              `FCM kirim gagal (token dipertahankan): ${code ?? "unknown"}`,
              r.error?.message,
            );
          }),
        );
      }
    } catch (err) {
      console.warn("FCM send failed:", err);
    }
  }
}
