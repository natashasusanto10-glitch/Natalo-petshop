"use client";

import { useEffect, useState } from "react";

function urlBase64ToUint8Array(base64String: string) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  return Uint8Array.from(Array.from(raw).map((c) => c.charCodeAt(0)));
}

type PushState = "loading" | "unsupported" | "denied" | "subscribed" | "idle";

/**
 * Push notification subscribe component — works di:
 * - iOS native (TestFlight/.ipa) → @capacitor/push-notifications + APNs
 * - Android native (.apk Play Store) → @capacitor/push-notifications + FCM
 * - PWA/Browser → Web Push (VAPID) via service worker (existing flow)
 *
 * Auto-detect platform pakai Capacitor.isNativePlatform() + getPlatform().
 * Plugin yang sama (@capacitor/push-notifications) handle iOS (APNs token)
 * dan Android (FCM token); kita branch berdasarkan platform untuk POST ke
 * route yang tepat dan simpan dgn prefix yang berbeda:
 * - iOS  → /api/push/subscribe-apns  (endpoint: "apns:<token>")
 * - Android → /api/push/subscribe-fcm (endpoint: "fcm:<token>")
 *
 * Web fallback: PushManager.subscribe() dengan VAPID key (existing flow).
 */
type NativePlatform = "ios" | "android" | null;

/**
 * Trigger `PushNotifications.register()` lalu POST token yang baru
 * di-receive ke /subscribe-apns atau /subscribe-fcm sesuai platform.
 *
 * Idempotent di sisi backend (upsert by endpoint). Aman dipanggil setiap
 * mount kalau permission sudah granted — fixes case di mana user dapat
 * permission tapi tokennya gak pernah ke-register ke server.
 *
 * Resolve ketika token sudah POST atau error (timeout 8 detik supaya
 * gak block UI selamanya kalau ada masalah Capacitor bridge).
 */
async function ensureNativeRegistered(platform: NativePlatform): Promise<void> {
  const { PushNotifications } = await import("@capacitor/push-notifications");

  const subscribeUrl =
    platform === "android"
      ? "/api/push/subscribe-fcm"
      : "/api/push/subscribe-apns";

  // Urutan kritis: listener HARUS attached SEBELUM register() dipanggil.
  // Kalau register() fire duluan, event "registration" dispatch ke listener
  // yang belum ada → token terbuang dan POST gak pernah terjadi.
  let resolveDone: () => void = () => {};
  const done = new Promise<void>((r) => {
    resolveDone = r;
  });
  let settled = false;
  const finish = () => {
    if (settled) return;
    settled = true;
    resolveDone();
  };

  // Untuk debugging dari prod: dispatch custom event "native-push-debug"
  // dengan info — caller di UI bisa surface ke admin kalau perlu.
  const debugLog = (stage: string, extra?: Record<string, unknown>) => {
    if (typeof window === "undefined") return;
    window.dispatchEvent(
      new CustomEvent("native-push-debug", { detail: { stage, ...extra } })
    );
  };

  debugLog("attach-listeners");

  const tokenHandle = await PushNotifications.addListener(
    "registration",
    async (token) => {
      debugLog("token-received", { tokenLen: token.value?.length ?? 0 });
      try {
        const res = await fetch(subscribeUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            token: token.value,
            platform: platform ?? "ios",
          }),
        });
        debugLog("token-posted", { status: res.status });
      } catch (err) {
        debugLog("token-post-failed", {
          error: err instanceof Error ? err.message : String(err),
        });
      }
      finish();
    }
  );

  const errorHandle = await PushNotifications.addListener(
    "registrationError",
    (err) => {
      debugLog("registration-error", { error: JSON.stringify(err) });
      finish();
    }
  );

  // Sekarang aman call register() — kedua listener pasti sudah attached.
  debugLog("calling-register");
  PushNotifications.register().catch((err) => {
    debugLog("register-rejected", {
      error: err instanceof Error ? err.message : String(err),
    });
    finish();
  });

  // Safety timeout: max 8 detik.
  await Promise.race([
    done,
    new Promise<void>((r) => setTimeout(r, 8000)).then(() => {
      debugLog("timeout-8s");
      finish();
    }),
  ]);

  await tokenHandle.remove().catch(() => {});
  await errorHandle.remove().catch(() => {});
}

export function PushSubscribe() {
  const [state, setState] = useState<PushState>("loading");
  const [isNative, setIsNative] = useState(false);
  const [nativePlatform, setNativePlatform] = useState<NativePlatform>(null);
  const vapidKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;

  useEffect(() => {
    let cancelled = false;

    (async () => {
      // Detect Capacitor native platform
      let nativeDetected = false;
      let platform: NativePlatform = null;
      try {
        const { Capacitor } = await import("@capacitor/core");
        nativeDetected = Capacitor.isNativePlatform();
        if (nativeDetected) {
          const p = Capacitor.getPlatform();
          if (p === "ios" || p === "android") platform = p;
        }
      } catch {
        // Web-only environment
      }
      if (cancelled) return;
      setIsNative(nativeDetected);
      setNativePlatform(platform);

      if (nativeDetected) {
        // Native iOS/Android: check OS-level push permission status.
        // Plugin sama untuk kedua platform — beda backend channel (APNs vs FCM)
        // di-handle saat subscribe via routing per platform.
        try {
          const { PushNotifications } = await import(
            "@capacitor/push-notifications"
          );
          const perm = await PushNotifications.checkPermissions();
          if (cancelled) return;
          if (perm.receive === "granted") {
            // PENTING: "granted" di OS != "token sudah ke-POST ke server".
            // User bisa granted dari install lama / TestFlight auto-grant,
            // tapi DB tetap kosong kalau register() belum pernah dipanggil.
            // Auto-trigger register() — idempotent (gak re-prompt), tokennya
            // akan datang via "registration" listener → POST upsert ke DB.
            await ensureNativeRegistered(platform);
            if (cancelled) return;
            setState("subscribed");
          } else if (perm.receive === "denied") {
            setState("denied");
          } else {
            setState("idle");
          }
        } catch {
          setState("unsupported");
        }
      } else {
        // Web: check Web Push subscription
        if (
          !("serviceWorker" in navigator) ||
          !("PushManager" in window) ||
          !vapidKey
        ) {
          setState("unsupported");
          return;
        }
        const reg = await navigator.serviceWorker.ready;
        if (cancelled) return;
        const sub = await reg.pushManager.getSubscription();
        setState(sub ? "subscribed" : "idle");
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [vapidKey]);

  async function subscribeNative() {
    try {
      const { PushNotifications } = await import(
        "@capacitor/push-notifications"
      );
      const perm = await PushNotifications.requestPermissions();
      if (perm.receive !== "granted") {
        setState("denied");
        return;
      }
      await ensureNativeRegistered(nativePlatform);
      setState("subscribed");
    } catch (err) {
      console.warn("Push subscribe (native) failed:", err);
      setState("denied");
    }
  }

  async function subscribeWeb() {
    if (!vapidKey) return;
    const reg = await navigator.serviceWorker.ready;
    try {
      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidKey),
      });
      await fetch("/api/push/subscribe", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(sub.toJSON()),
      });
      setState("subscribed");
    } catch {
      setState("denied");
    }
  }

  async function subscribe() {
    if (isNative) {
      await subscribeNative();
    } else {
      await subscribeWeb();
    }
  }

  async function unsubscribe() {
    if (isNative) {
      // Native user (iOS/Android) disable di OS Settings; kita gak bisa
      // programmatically revoke APNs/FCM token dari plugin. Kasih instruksi
      // sesuai platform.
      const msg =
        nativePlatform === "android"
          ? "Untuk matikan notifikasi, buka Settings Android → Apps → Natalo Petshop → Notifications → matikan."
          : "Untuk matikan notifikasi, buka Settings iPhone → Natalo Petshop → Notifications → matikan toggle 'Allow Notifications'.";
      alert(msg);
      return;
    }
    const reg = await navigator.serviceWorker.ready;
    const sub = await reg.pushManager.getSubscription();
    if (sub) {
      await fetch("/api/push/subscribe", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ endpoint: sub.endpoint }),
      });
      await sub.unsubscribe();
    }
    setState("idle");
  }

  if (state === "loading") {
    return (
      <button
        type="button"
        disabled
        className="flex w-full items-center justify-center gap-2 rounded-2xl border border-zinc-200 bg-zinc-100 px-4 py-3 text-sm font-semibold text-zinc-400"
      >
        Memeriksa notifikasi...
      </button>
    );
  }

  if (state === "unsupported") {
    return (
      <button
        type="button"
        disabled
        className="flex w-full items-center justify-center gap-2 rounded-2xl border border-zinc-200 bg-zinc-100 px-4 py-3 text-sm font-semibold text-zinc-400"
      >
        Aktifkan notifikasi
      </button>
    );
  }

  if (state === "subscribed") {
    return (
      <div className="flex items-center justify-between rounded-2xl bg-green-50 px-4 py-3 text-sm">
        <span className="font-semibold text-green-700">
          Notifikasi aplikasi aktif
        </span>
        <button
          onClick={unsubscribe}
          className="text-xs text-gray-400 hover:text-red-500"
        >
          Settings HP
        </button>
      </div>
    );
  }

  if (state === "denied") {
    const deniedMsg = isNative
      ? nativePlatform === "android"
        ? "Notifikasi diblokir. Aktifkan di Settings Android → Apps → Natalo Petshop → Notifications."
        : "Notifikasi diblokir. Aktifkan di Settings iPhone → Natalo Petshop → Notifications."
      : "Notifikasi diblokir. Aktifkan di pengaturan browser.";
    return <p className="text-sm text-red-500">{deniedMsg}</p>;
  }

  return (
    <button
      onClick={subscribe}
      className="flex w-full items-center justify-center gap-2 rounded-2xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm font-semibold text-blue-600 transition hover:bg-blue-100"
    >
      Aktifkan notifikasi aplikasi
    </button>
  );
}
