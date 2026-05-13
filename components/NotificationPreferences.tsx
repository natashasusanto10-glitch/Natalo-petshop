"use client";

import { useEffect, useState } from "react";
import { PushSubscribe } from "@/components/PushSubscribe";

type PreferenceKey = "orders" | "promos" | "chat" | "favorites";

const STORAGE_KEY = "natalo-notification-preferences";

const PREFERENCES: { key: PreferenceKey; label: string }[] = [
  { key: "orders", label: "Notifikasi pesanan" },
  { key: "promos", label: "Notifikasi promo" },
  { key: "chat", label: "Notifikasi chat toko" },
  { key: "favorites", label: "Notifikasi produk favorit" },
];

type PreferenceState = Record<PreferenceKey, boolean>;

const DEFAULT_PREFERENCES: PreferenceState = {
  orders: true,
  promos: true,
  chat: true,
  favorites: true,
};

export function NotificationPreferences() {
  const [preferences, setPreferences] = useState<PreferenceState>(DEFAULT_PREFERENCES);

  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(STORAGE_KEY);
      if (!stored) return;
      const parsed = JSON.parse(stored) as Partial<PreferenceState>;
      setPreferences({ ...DEFAULT_PREFERENCES, ...parsed });
    } catch {
      setPreferences(DEFAULT_PREFERENCES);
    }
  }, []);

  function toggle(key: PreferenceKey) {
    setPreferences((prev) => {
      const next = { ...prev, [key]: !prev[key] };
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      return next;
    });
  }

  return (
    <div className="space-y-4">
      <section className="rounded-2xl border border-zinc-100 bg-white p-5 shadow-sm">
        <h2 className="font-bold text-zinc-950">Notifikasi aplikasi</h2>
        <p className="mt-1 text-sm text-zinc-500">Notifikasi aktif di perangkat</p>
        <div className="mt-4">
          <PushSubscribe />
        </div>
      </section>

      <section className="rounded-2xl border border-zinc-100 bg-white p-5 shadow-sm">
        <h2 className="font-bold text-zinc-950">Preferensi notifikasi</h2>
        <div className="mt-4 divide-y divide-zinc-100">
          {PREFERENCES.map((item) => (
            <label
              key={item.key}
              className="flex items-center justify-between gap-4 py-3 first:pt-0 last:pb-0"
            >
              <span className="text-sm font-semibold text-zinc-800">{item.label}</span>
              <button
                type="button"
                role="switch"
                aria-checked={preferences[item.key]}
                onClick={() => toggle(item.key)}
                className={`relative h-7 w-12 rounded-full transition ${
                  preferences[item.key] ? "bg-blue-500" : "bg-zinc-200"
                }`}
              >
                <span
                  aria-hidden
                  className={`absolute top-1 h-5 w-5 rounded-full bg-white shadow transition ${
                    preferences[item.key] ? "left-6" : "left-1"
                  }`}
                />
              </button>
            </label>
          ))}
        </div>
      </section>
    </div>
  );
}
