"use client";

import { useEffect, useState } from "react";
import { registerPushForCurrentUser } from "@/lib/push-client";

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

function statusCopy(status: string | null) {
  switch (status) {
    case "registered":
      return "Notifikasi aktif di perangkat ini.";
    case "denied":
      return "Izin notifikasi diblokir. Aktifkan dari Settings HP/browser.";
    case "prompt":
      return "Izin belum diberikan. Tekan tombol aktifkan untuk meminta izin.";
    case "unsupported":
      return "Perangkat/browser ini belum mendukung push notification.";
    case "error":
      return "Belum bisa mengaktifkan notifikasi. Coba lagi nanti.";
    default:
      return "Aktifkan notifikasi agar update penting masuk langsung ke HP.";
  }
}

export function NotificationSettingsClient() {
  const [preferences, setPreferences] =
    useState<Preferences>(DEFAULT_PREFERENCES);
  const [status, setStatus] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    setPreferences(readPreferences());
    void registerPushForCurrentUser({ prompt: false }).then(setStatus);
  }, []);

  function updatePreference(key: PreferenceKey, value: boolean) {
    const next = { ...preferences, [key]: value };
    setPreferences(next);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  }

  async function enablePush() {
    setLoading(true);
    const result = await registerPushForCurrentUser({ prompt: true });
    setStatus(result);
    setLoading(false);
  }

  return (
    <div className="space-y-5">
      <section className="rounded-3xl border border-blue-100 bg-blue-50 p-5">
        <div className="flex items-start gap-3">
          <p className="flex-1 text-sm font-black text-blue-900">
            Notifikasi aplikasi
          </p>
          {status === "registered" && (
            <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-green-100 px-2.5 py-1 text-xs font-bold text-green-700">
              <span className="h-1.5 w-1.5 rounded-full bg-green-500" />
              Aktif
            </span>
          )}
        </div>
        <p className="mt-2 text-sm leading-6 text-blue-800">
          {statusCopy(status)}
        </p>

        {/* Button hanya muncul saat user PERLU action: belum prompt,
            denied, error. Saat "registered" → status badge sudah cukup,
            button "Aktifkan" tidak relevan (akan no-op). Saat
            "unsupported" → device tidak support sama sekali, button
            tidak akan bantu. */}
        {(status === "prompt" || status === "denied" || status === "error" || status === null) && (
          <button
            type="button"
            onClick={enablePush}
            disabled={loading}
            className="mt-4 inline-flex w-full items-center justify-center rounded-full bg-blue-600 px-5 py-3 text-sm font-black text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:bg-blue-300"
          >
            {loading
              ? "Memeriksa izin..."
              : status === "denied"
                ? "Coba minta izin lagi"
                : "Aktifkan notifikasi perangkat"}
          </button>
        )}

        {status === "denied" && (
          <p className="mt-3 text-xs leading-5 text-blue-700/80">
            Kalau popup izin tidak muncul, buka iPhone Settings →
            Notifications → Natalo Petshop → Allow Notifications.
          </p>
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
        Pengaturan izin utama tetap mengikuti Settings HP. Preferensi di sini
        disimpan untuk aplikasi dan bisa dipakai saat kategori notifikasi promo,
        chat, atau produk favorit mulai dikirim dari backend.
      </p>
    </div>
  );
}
