"use client";

import { useEffect, useState } from "react";

type PreferenceKey = "orders" | "promo" | "chat" | "favorites";

type Preferences = Record<PreferenceKey, boolean>;

const STORAGE_KEY = "natalo-notification-preferences";

const DEFAULT_PREFERENCES: Preferences = {
  orders: true,
  promo: true,
  chat: true,
  favorites: true,
};

const OPTIONS: Array<{
  key: PreferenceKey;
  label: string;
  description: string;
}> = [
  {
    key: "orders",
    label: "Notifikasi pesanan",
    description:
      "Pembayaran, diproses, dikirim, selesai, dibatalkan, dan refund.",
  },
  {
    key: "promo",
    label: "Notifikasi promo",
    description: "Voucher, campaign, dan penawaran khusus.",
  },
  {
    key: "chat",
    label: "Notifikasi chat toko",
    description: "Balasan dari admin atau customer service.",
  },
  {
    key: "favorites",
    label: "Notifikasi produk favorit",
    description: "Update stok atau harga produk yang kamu simpan.",
  },
];

function readPreferences(): Preferences {
  if (typeof window === "undefined") return DEFAULT_PREFERENCES;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_PREFERENCES;
    const parsed = JSON.parse(raw) as Partial<Preferences>;
    return { ...DEFAULT_PREFERENCES, ...parsed };
  } catch {
    return DEFAULT_PREFERENCES;
  }
}

type TestPushResult = {
  ok: boolean;
  subscriptionCount?: { web: number; apns: number; fcm: number; total: number };
  results?: {
    web: Array<{ endpointHint: string; status: string; statusCode?: number; error?: string }>;
    apns: Array<{
      tokenHint: string;
      status: string;
      sentCount?: number;
      reason?: string;
      statusCode?: number;
      createdAt?: string;
    }>;
    fcm: Array<{ tokenHint: string; status: string; errorCode?: string; errorMsg?: string }>;
  };
  hint?: string;
  error?: string;
};

type ClientDiagnostic = {
  platform: string;
  isNative: boolean;
  notificationPermission: string;
  serviceWorkerRegistered: boolean;
  vapidPublicConfigured: boolean;
  currentTokenHint: string | null;
  tokenSource: "fresh-register" | "no-token" | "error" | "n/a";
  error?: string;
};

export function NotificationSettingsClient() {
  const [preferences, setPreferences] =
    useState<Preferences>(DEFAULT_PREFERENCES);
  const [testResult, setTestResult] = useState<TestPushResult | null>(null);
  const [testing, setTesting] = useState(false);
  const [clientDiag, setClientDiag] = useState<ClientDiagnostic | null>(null);
  const [diagLoading, setDiagLoading] = useState(false);

  useEffect(() => {
    setPreferences(readPreferences());
  }, []);

  async function runClientDiagnostic() {
    setDiagLoading(true);
    setClientDiag(null);

    const diag: ClientDiagnostic = {
      platform: "web",
      isNative: false,
      notificationPermission: "unknown",
      serviceWorkerRegistered: false,
      vapidPublicConfigured: Boolean(process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY),
      currentTokenHint: null,
      tokenSource: "n/a",
    };

    try {
      // Capacitor native detect
      let isNative = false;
      try {
        const { Capacitor } = await import("@capacitor/core");
        isNative = Capacitor.isNativePlatform();
        diag.platform = Capacitor.getPlatform();
        diag.isNative = isNative;
      } catch {
        diag.platform = "web";
      }

      if (isNative) {
        const { PushNotifications } = await import(
          "@capacitor/push-notifications"
        );
        const perm = await PushNotifications.checkPermissions();
        diag.notificationPermission = perm.receive;

        if (perm.receive === "granted") {
          // Call register() and capture token via listener. Timeout 10s.
          let token: string | null = null;
          const tokenHandle = await PushNotifications.addListener(
            "registration",
            (t) => {
              token = t.value;
            },
          );
          const errorHandle = await PushNotifications.addListener(
            "registrationError",
            () => {},
          );
          try {
            await PushNotifications.register();
          } catch {}
          await new Promise<void>((r) => setTimeout(r, 5000));
          await tokenHandle.remove().catch(() => {});
          await errorHandle.remove().catch(() => {});
          if (token) {
            const t = token as string;
            diag.currentTokenHint = `${t.slice(0, 8)}…${t.slice(-6)}`;
            diag.tokenSource = "fresh-register";
          } else {
            diag.tokenSource = "no-token";
          }
        }
      } else {
        // Web: SW + Notification API + PushManager subscription
        if ("Notification" in window) {
          diag.notificationPermission = Notification.permission;
        }
        if ("serviceWorker" in navigator) {
          const reg = await navigator.serviceWorker.getRegistration();
          diag.serviceWorkerRegistered = Boolean(reg);
          if (reg && "PushManager" in window) {
            const sub = await reg.pushManager.getSubscription();
            if (sub) {
              const ep = sub.endpoint;
              diag.currentTokenHint = `${ep.slice(0, 24)}…${ep.slice(-8)}`;
              diag.tokenSource = "fresh-register";
            } else {
              diag.tokenSource = "no-token";
            }
          }
        }
      }
    } catch (err) {
      diag.error = err instanceof Error ? err.message : String(err);
    } finally {
      setClientDiag(diag);
      setDiagLoading(false);
    }
  }

  function updatePreference(key: PreferenceKey, value: boolean) {
    const next = { ...preferences, [key]: value };
    setPreferences(next);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  }

  async function runTestPush() {
    setTesting(true);
    setTestResult(null);
    try {
      const res = await fetch("/api/push/me/test", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({}),
      });
      const data = (await res.json()) as TestPushResult;
      setTestResult(data);
    } catch (err) {
      setTestResult({
        ok: false,
        error: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setTesting(false);
    }
  }

  return (
    <div className="space-y-5">
      <section className="rounded-3xl border border-purple-100 bg-purple-50 p-5">
        <p className="font-black text-purple-900">
          Diagnostic: State device ini
        </p>
        <p className="mt-2 text-xs leading-5 text-purple-800">
          Cek state push di device (permission iOS, current token, dll).
          Bandingkan currentTokenHint dengan tokenHint di hasil &quot;Test
          push&quot;. Kalau beda &rarr; DB punya token lama, device punya
          token baru &rarr; bug di registrasi.
        </p>
        <button
          type="button"
          onClick={runClientDiagnostic}
          disabled={diagLoading}
          className="mt-4 inline-flex w-full items-center justify-center rounded-full bg-purple-600 px-5 py-3 text-sm font-black text-white hover:bg-purple-700 disabled:cursor-not-allowed disabled:bg-purple-300"
        >
          {diagLoading ? "Memeriksa..." : "Cek state device"}
        </button>

        {clientDiag && (
          <pre className="mt-4 max-h-80 overflow-auto rounded-xl bg-white p-3 text-[11px] leading-relaxed text-gray-800 ring-1 ring-purple-200">
            {JSON.stringify(clientDiag, null, 2)}
          </pre>
        )}
      </section>

      <section className="rounded-3xl border border-blue-100 bg-blue-50 p-5">
        <p className="font-black text-blue-900">Diagnostic: Test push ke device ini</p>
        <p className="mt-2 text-xs leading-5 text-blue-800">
          Trigger push langsung ke semua subscription milik akun kamu. Berguna
          untuk debug kalau notif tidak masuk — response akan kasih tau apakah
          server-side OK, dan kalau ada error apa reason-nya dari APNs/FCM.
        </p>
        <button
          type="button"
          onClick={runTestPush}
          disabled={testing}
          className="mt-4 inline-flex w-full items-center justify-center rounded-full bg-blue-600 px-5 py-3 text-sm font-black text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-300"
        >
          {testing ? "Mengirim..." : "Test push sekarang"}
        </button>

        {testResult && (
          <pre className="mt-4 max-h-80 overflow-auto rounded-xl bg-white p-3 text-[11px] leading-relaxed text-gray-800 ring-1 ring-blue-200">
            {JSON.stringify(testResult, null, 2)}
          </pre>
        )}
      </section>

      <section className="rounded-3xl border border-gray-100 bg-white p-5 shadow-sm">
        <p className="font-black text-gray-950">Preferensi notifikasi</p>
        <div className="mt-4 divide-y divide-gray-100">
          {OPTIONS.map((option) => (
            <label
              key={option.key}
              className="flex items-center justify-between gap-4 py-4"
            >
              <span>
                <span className="block text-sm font-bold text-gray-900">
                  {option.label}
                </span>
                <span className="mt-1 block text-xs leading-5 text-gray-500">
                  {option.description}
                </span>
              </span>
              <input
                type="checkbox"
                checked={preferences[option.key]}
                onChange={(event) =>
                  updatePreference(option.key, event.target.checked)
                }
                className="h-5 w-5 shrink-0 rounded border-gray-300 text-blue-600"
              />
            </label>
          ))}
        </div>
      </section>

      <p className="px-1 text-xs leading-5 text-gray-500">
        Preferensi di halaman ini mengatur kategori notifikasi dari aplikasi
        Natalo. Izin notifikasi perangkat tetap mengikuti pengaturan HP.
      </p>
    </div>
  );
}
