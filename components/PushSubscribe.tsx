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
 * - PWA/Browser → Web Push (VAPID) via service worker (existing flow)
 *
 * Auto-detect platform pakai Capacitor.isNativePlatform() check via dynamic
 * import. Kalau native, register APNs token via plugin, kirim ke backend
 * /api/push/subscribe-apns (endpoint: "apns:" + token). Kalau web, fallback
 * ke PushManager.subscribe() dengan VAPID key (kayak sebelumnya).
 */
export function PushSubscribe() {
  const [state, setState] = useState<PushState>("loading");
  const [isNative, setIsNative] = useState(false);
  const vapidKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;

  useEffect(() => {
    let cancelled = false;

    (async () => {
      // Detect Capacitor native platform
      let nativeDetected = false;
      try {
        const { Capacitor } = await import("@capacitor/core");
        nativeDetected = Capacitor.isNativePlatform();
      } catch {
        // Web-only environment
      }
      if (cancelled) return;
      setIsNative(nativeDetected);

      if (nativeDetected) {
        // Native iOS: check APNs permission status
        try {
          const { PushNotifications } = await import("@capacitor/push-notifications");
          const perm = await PushNotifications.checkPermissions();
          if (cancelled) return;
          if (perm.receive === "granted") {
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
        if (!("serviceWorker" in navigator) || !("PushManager" in window) || !vapidKey) {
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
      const { PushNotifications } = await import("@capacitor/push-notifications");

      // Request permission
      const perm = await PushNotifications.requestPermissions();
      if (perm.receive !== "granted") {
        setState("denied");
        return;
      }

      // Setup token listener BEFORE register, so we catch the token event
      const tokenHandle = await PushNotifications.addListener(
        "registration",
        async (token) => {
          // Send APNs token ke backend, simpan di PushSubscription dengan prefix "apns:"
          await fetch("/api/push/subscribe-apns", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              token: token.value,
              platform: "ios",
            }),
          });
          setState("subscribed");
          // Cleanup listener setelah token diterima (stable, gak perlu listen lagi)
          tokenHandle.remove();
        },
      );

      const errorHandle = await PushNotifications.addListener(
        "registrationError",
        (err) => {
          console.warn("APNs registration failed:", err);
          setState("denied");
          errorHandle.remove();
        },
      );

      // Trigger registration — APNs server akan kasih token via "registration" listener
      await PushNotifications.register();
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
      // iOS user can disable di Settings; kita gak bisa programmatically
      // remove APNs token. Kasih instruksi.
      alert(
        "Untuk matikan notifikasi, buka Settings iPhone → Natalo Petshop → Notifications → matikan toggle 'Allow Notifications'.",
      );
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

  if (state === "loading" || state === "unsupported") return null;

  if (state === "subscribed") {
    return (
      <div className="flex items-center justify-between rounded-2xl bg-green-50 px-4 py-3 text-sm">
        <span className="font-semibold text-green-700">🔔 Notifikasi order aktif</span>
        <button onClick={unsubscribe} className="text-xs text-gray-400 hover:text-red-500">
          Matikan
        </button>
      </div>
    );
  }

  if (state === "denied") {
    return (
      <p className="text-sm text-red-500">
        {isNative
          ? "Notifikasi diblokir. Aktifkan di Settings iPhone → Natalo Petshop → Notifications."
          : "Notifikasi diblokir. Aktifkan di pengaturan browser."}
      </p>
    );
  }

  return (
    <button
      onClick={subscribe}
      className="flex w-full items-center justify-center gap-2 rounded-2xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm font-semibold text-blue-600 transition hover:bg-blue-100"
    >
      🔔 Aktifkan notifikasi update pesanan
    </button>
  );
}
