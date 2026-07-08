import { cert, getApp, getApps, initializeApp, type App } from "firebase-admin/app";
import { getAuth, type Auth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { normalizePemKey } from "../pem-utils";

/**
 * Firestore Admin client — project `tokochat-a8879` (Customer Chat).
 *
 * INI ADALAH APP ADMIN SDK TERPISAH dari `natalo-fcm` (lihat lib/fcm.ts,
 * project `natalopetshop`). Dua project Firebase yang berbeda, dua service
 * account yang berbeda — JANGAN campur kredensial:
 * - natalo-fcm   → FCM_*      → project natalopetshop (push notification)
 * - tokochat     → TOKOCHAT_* → project tokochat-a8879 (customer chat Firestore)
 *
 * Setup via env vars (dari Firebase Console tokochat-a8879 → Project Settings
 * → Service accounts → Generate new private key):
 * - TOKOCHAT_PROJECT_ID
 * - TOKOCHAT_CLIENT_EMAIL
 * - TOKOCHAT_PRIVATE_KEY (PEM — boleh literal "\n", di-normalize di bawah
 *   pakai helper yang sama dengan lib/fcm.ts, lihat lib/pem-utils.ts)
 *
 * Init lazy: memanggil module ini TIDAK menyentuh Firebase sama sekali.
 * initializeApp() baru dipanggil saat getTokochatFirestore() pertama kali
 * dipanggil, dan hasilnya di-cache (singleton) untuk request-request
 * berikutnya dalam proses yang sama.
 */

const APP_NAME = "tokochat";

function getTokochatApp(): App {
  const existing = getApps().find((a) => a.name === APP_NAME);
  if (existing) return getApp(APP_NAME);

  const projectId = process.env.TOKOCHAT_PROJECT_ID;
  const clientEmail = process.env.TOKOCHAT_CLIENT_EMAIL;
  const privateKey = process.env.TOKOCHAT_PRIVATE_KEY;
  if (!projectId || !clientEmail || !privateKey) {
    throw new Error("Kredensial tokochat (TOKOCHAT_*) belum di-set.");
  }

  return initializeApp(
    {
      credential: cert({
        projectId,
        clientEmail,
        privateKey: normalizePemKey(privateKey),
      }),
    },
    APP_NAME,
  );
}

let cached: Firestore | null = null;

export function getTokochatFirestore(): Firestore {
  if (cached) return cached;
  cached = getFirestore(getTokochatApp());
  return cached;
}

let cachedAuth: Auth | null = null;

export function getTokochatAuth(): Auth {
  if (cachedAuth) return cachedAuth;
  cachedAuth = getAuth(getTokochatApp());
  return cachedAuth;
}
