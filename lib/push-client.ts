type NativePlatform = "ios" | "android" | null;

type PushRegistrationResult =
  | "registered"
  | "prompt"
  | "denied"
  | "unsupported"
  | "error";

const ALLOWED_PUSH_HOSTS = new Set([
  "localhost",
  "127.0.0.1",
  "natalo-petshop.vercel.app",
  "natalopetshop.com",
  "www.natalopetshop.com",
]);

function readString(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object"
    ? (value as Record<string, unknown>)
    : {};
}

export function getInternalPushPath(rawUrl: string | null | undefined) {
  const value = readString(rawUrl);
  if (!value) return null;

  const base =
    typeof window !== "undefined"
      ? window.location.origin
      : "https://natalopetshop.com";

  try {
    const url = new URL(value, base);
    const currentHost =
      typeof window !== "undefined" ? window.location.hostname : null;
    const allowed =
      url.origin === base ||
      ALLOWED_PUSH_HOSTS.has(url.hostname) ||
      (currentHost ? url.hostname === currentHost : false);

    if (!allowed) return null;
    if (url.pathname === "/admin" || url.pathname.startsWith("/admin/")) {
      return null;
    }

    return `${url.pathname || "/"}${url.search}${url.hash}`;
  } catch {
    return null;
  }
}

export function getPushNavigationTarget(data: unknown) {
  const payload = asRecord(data);
  const nested = asRecord(payload.data);
  const candidates = [
    readString(payload.url),
    readString(nested.url),
    readString(payload.path),
    readString(nested.path),
    readString(payload.link),
    readString(nested.link),
  ];

  for (const candidate of candidates) {
    const path = getInternalPushPath(candidate);
    if (path) return path;
  }

  const orderNumber =
    readString(payload.order_number) ||
    readString(payload.orderNumber) ||
    readString(nested.order_number) ||
    readString(nested.orderNumber);

  return orderNumber ? `/pesanan/${encodeURIComponent(orderNumber)}` : null;
}

async function detectNativePlatform(): Promise<NativePlatform> {
  try {
    const { Capacitor } = await import("@capacitor/core");
    if (!Capacitor.isNativePlatform()) return null;
    const platform = Capacitor.getPlatform();
    return platform === "ios" || platform === "android" ? platform : null;
  } catch {
    return null;
  }
}

async function postNativeToken(token: string, platform: NativePlatform) {
  const url =
    platform === "android"
      ? "/api/push/subscribe-fcm"
      : "/api/push/subscribe-apns";

  console.log("[push-client] posting token", {
    platform,
    url,
    tokenPreview: token.slice(0, 12) + "...",
  });

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({ token, platform: platform ?? "ios" }),
    });
    console.log("[push-client] token POST result", {
      status: res.status,
      ok: res.ok,
    });
    // Fire-and-forget beacon ke server log endpoint biar status keliatan
    // di Vercel Logs (tanpa butuh Safari Web Inspector).
    fetch("/api/debug/push-trace", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({
        event: "token-posted",
        platform,
        status: res.status,
        ok: res.ok,
      }),
    }).catch(() => {});
  } catch (err) {
    console.error("[push-client] token POST failed", err);
    fetch("/api/debug/push-trace", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({
        event: "token-post-error",
        platform,
        error: String(err),
      }),
    }).catch(() => {});
  }
}

async function ensureNativeRegistered(platform: NativePlatform) {
  const { PushNotifications } = await import("@capacitor/push-notifications");

  let resolveDone: () => void = () => {};
  const done = new Promise<void>((resolve) => {
    resolveDone = resolve;
  });
  let settled = false;
  const finish = () => {
    if (settled) return;
    settled = true;
    resolveDone();
  };

  const tokenHandle = await PushNotifications.addListener(
    "registration",
    async (token) => {
      try {
        await postNativeToken(token.value, platform);
      } finally {
        finish();
      }
    }
  );

  const errorHandle = await PushNotifications.addListener(
    "registrationError",
    () => finish()
  );

  PushNotifications.register().catch(() => finish());

  await Promise.race([
    done,
    new Promise<void>((resolve) => setTimeout(resolve, 8000)).then(finish),
  ]);

  await tokenHandle.remove().catch(() => {});
  await errorHandle.remove().catch(() => {});
}

async function logTrace(event: string, data?: Record<string, unknown>) {
  console.log("[push-client]", event, data ?? "");
  try {
    await fetch("/api/debug/push-trace", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({ event, ...(data ?? {}) }),
    });
  } catch {
    // ignore — diagnostic only
  }
}

export async function registerNativePushForCurrentUser(
  prompt: boolean
): Promise<PushRegistrationResult> {
  const platform = await detectNativePlatform();
  if (!platform) {
    void logTrace("register-skip-not-native");
    return "unsupported";
  }
  void logTrace("register-start", { platform, prompt });

  try {
    const { PushNotifications } = await import("@capacitor/push-notifications");
    let permission = (await PushNotifications.checkPermissions()).receive;
    void logTrace("permission-checked", { permission });

    if (permission !== "granted") {
      if (!prompt) return permission === "denied" ? "denied" : "prompt";
      permission = (await PushNotifications.requestPermissions()).receive;
      void logTrace("permission-requested", { permission });
    }

    if (permission !== "granted") {
      void logTrace("register-denied", { permission });
      return permission === "denied" ? "denied" : "prompt";
    }

    await ensureNativeRegistered(platform);
    void logTrace("register-complete", { platform });
    return "registered";
  } catch (err) {
    void logTrace("register-error", { error: String(err) });
    return "error";
  }
}

export async function registerWebPushForCurrentUser(
  prompt: boolean
): Promise<PushRegistrationResult> {
  if (
    typeof window === "undefined" ||
    !("serviceWorker" in navigator) ||
    !("PushManager" in window)
  ) {
    return "unsupported";
  }

  const vapidKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;
  if (!vapidKey) return "unsupported";

  try {
    if ("Notification" in window) {
      if (Notification.permission === "denied") return "denied";
      if (Notification.permission === "default") {
        if (!prompt) return "prompt";
        const nextPermission = await Notification.requestPermission();
        if (nextPermission !== "granted") {
          return nextPermission === "denied" ? "denied" : "prompt";
        }
      }
    }

    const registration = await navigator.serviceWorker.ready;
    let subscription = await registration.pushManager.getSubscription();

    if (!subscription) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidKey),
      });
    }

    await fetch("/api/push/subscribe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify(subscription.toJSON()),
    });

    return "registered";
  } catch {
    return "error";
  }
}

export async function registerPushForCurrentUser(params?: {
  prompt?: boolean;
}): Promise<PushRegistrationResult> {
  const nativeResult = await registerNativePushForCurrentUser(
    params?.prompt ?? false
  );
  if (nativeResult !== "unsupported") return nativeResult;
  return registerWebPushForCurrentUser(params?.prompt ?? false);
}

function urlBase64ToUint8Array(base64String: string) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  return Uint8Array.from(Array.from(raw).map((c) => c.charCodeAt(0)));
}
