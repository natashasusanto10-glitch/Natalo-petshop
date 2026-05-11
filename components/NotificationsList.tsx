"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

type Notification = {
  id: string;
  title: string;
  body: string;
  url: string | null;
  segment: string;
  createdAt: string;
  read: boolean;
};

type FetchResponse = {
  ok: boolean;
  loggedIn: boolean;
  unreadCount: number;
  items: Notification[];
  error?: string;
};

/**
 * Format waktu relatif ringkas: "baru saja", "5 menit lalu", "2 jam lalu",
 * "kemarin", "3 hari lalu", "12 Mei 2026". Tidak pakai library — Date arith
 * cukup untuk granularitas yg dibutuhkan di notif center.
 */
function formatRelativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(diff / 60_000);
  if (minutes < 1) return "baru saja";
  if (minutes < 60) return `${minutes} menit lalu`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} jam lalu`;
  const days = Math.floor(hours / 24);
  if (days === 1) return "kemarin";
  if (days < 7) return `${days} hari lalu`;
  return new Date(iso).toLocaleDateString("id-ID", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

export function NotificationsList() {
  const [items, setItems] = useState<Notification[] | null>(null);
  const [loggedIn, setLoggedIn] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const res = await fetch("/api/notifications/me", { cache: "no-store" });
      if (!res.ok) {
        setError(`Gagal load (HTTP ${res.status})`);
        return;
      }
      const data = (await res.json()) as FetchResponse;
      if (!data.ok) {
        setError(data.error ?? "Gagal load");
        return;
      }
      setItems(data.items);
      setLoggedIn(data.loggedIn);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Network error");
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  // Optimistic mark-as-read — update UI dulu sebelum API balas. Kalau API
  // gagal, fire-and-forget; user akan lihat status terkini next refresh.
  // Dispatch event "notifications-updated" supaya bell di header sync
  // (unread count berkurang).
  async function handleTap(notif: Notification) {
    if (!loggedIn || notif.read) return;
    setItems((prev) =>
      prev ? prev.map((i) => (i.id === notif.id ? { ...i, read: true } : i)) : prev,
    );
    if (typeof window !== "undefined") {
      window.dispatchEvent(new Event("notifications-updated"));
    }
    void fetch(`/api/notifications/${notif.id}/read`, { method: "POST" }).catch(() => {});
  }

  if (error) {
    return (
      <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
        {error}
      </div>
    );
  }

  if (items === null) {
    return (
      <div className="space-y-3">
        {[1, 2, 3].map((i) => (
          <div key={i} className="h-20 animate-pulse rounded-2xl bg-zinc-100" />
        ))}
      </div>
    );
  }

  if (items.length === 0) {
    return (
      <div className="rounded-2xl border border-zinc-200 bg-white px-6 py-12 text-center">
        <div className="mx-auto h-12 w-12 text-zinc-300">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M14.857 17.082a23.848 23.848 0 0 0 5.454-1.31A8.967 8.967 0 0 1 18 9.75V9A6 6 0 0 0 6 9v.75a8.967 8.967 0 0 1-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 0 1-5.714 0m5.714 0a3 3 0 1 1-5.714 0"
            />
          </svg>
        </div>
        <p className="mt-3 text-sm font-semibold text-zinc-700">Belum ada notifikasi</p>
        <p className="mt-1 text-xs text-zinc-500">
          Update pesanan dan promo akan muncul di sini.
        </p>
      </div>
    );
  }

  return (
    <ul className="space-y-2">
      {items.map((notif) => {
        const content = (
          <div
            className={`rounded-2xl border px-4 py-3 transition ${
              notif.read
                ? "border-zinc-200 bg-white"
                : "border-natalo-200 bg-natalo-50/50"
            }`}
          >
            <div className="flex items-start gap-3">
              {!notif.read && (
                <span
                  aria-label="Belum dibaca"
                  className="mt-1.5 inline-block h-2 w-2 shrink-0 rounded-full bg-natalo-500"
                />
              )}
              <div className="min-w-0 flex-1">
                <p
                  className={`text-sm ${
                    notif.read ? "font-semibold text-zinc-700" : "font-bold text-zinc-900"
                  }`}
                >
                  {notif.title}
                </p>
                <p className="mt-0.5 line-clamp-3 text-sm text-zinc-600">{notif.body}</p>
                <p className="mt-1.5 text-xs text-zinc-400">
                  {formatRelativeTime(notif.createdAt)}
                </p>
              </div>
            </div>
          </div>
        );

        if (notif.url) {
          return (
            <li key={notif.id}>
              <Link href={notif.url} onClick={() => handleTap(notif)} className="block">
                {content}
              </Link>
            </li>
          );
        }
        return (
          <li key={notif.id}>
            <button type="button" onClick={() => handleTap(notif)} className="block w-full text-left">
              {content}
            </button>
          </li>
        );
      })}
    </ul>
  );
}
