"use client";

import { useEffect, useState } from "react";

function urlBase64ToUint8Array(base64String: string) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  return Uint8Array.from(Array.from(raw).map((c) => c.charCodeAt(0)));
}

export function PushSubscribe() {
  const [state, setState] = useState<"loading" | "unsupported" | "denied" | "subscribed" | "idle">("loading");
  const vapidKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;

  useEffect(() => {
    if (!("serviceWorker" in navigator) || !("PushManager" in window) || !vapidKey) {
      setState("unsupported");
      return;
    }
    navigator.serviceWorker.ready.then(async (reg) => {
      const sub = await reg.pushManager.getSubscription();
      setState(sub ? "subscribed" : "idle");
    });
  }, [vapidKey]);

  async function subscribe() {
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

  async function unsubscribe() {
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

  if (state === "loading" || state === "unsupported" || !vapidKey) return null;

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
      <p className="text-sm text-red-500">Notifikasi diblokir. Aktifkan di pengaturan browser.</p>
    );
  }

  return (
    <button
      onClick={subscribe}
      className="flex w-full items-center justify-center gap-2 rounded-2xl border border-orange-200 bg-orange-50 px-4 py-3 text-sm font-semibold text-orange-600 transition hover:bg-orange-100"
    >
      🔔 Aktifkan notifikasi update pesanan
    </button>
  );
}
