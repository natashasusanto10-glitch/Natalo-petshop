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

export function NotificationSettingsClient() {
  const [preferences, setPreferences] =
    useState<Preferences>(DEFAULT_PREFERENCES);

  useEffect(() => {
    setPreferences(readPreferences());
  }, []);

  function updatePreference(key: PreferenceKey, value: boolean) {
    const next = { ...preferences, [key]: value };
    setPreferences(next);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  }

  return (
    <div className="space-y-5">
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
