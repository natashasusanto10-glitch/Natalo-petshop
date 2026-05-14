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

export function NotificationSettingsClient() {
  const [preferences, setPreferences] =
    useState<Preferences>(DEFAULT_PREFERENCES);
  const [testResult, setTestResult] = useState<TestPushResult | null>(null);
  const [testing, setTesting] = useState(false);

  useEffect(() => {
    setPreferences(readPreferences());
  }, []);

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
