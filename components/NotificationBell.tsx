"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { IoNotificationsOutline } from "react-icons/io5";

/**
 * Bell icon untuk header — link ke /notifications dgn badge unread count.
 *
 * Fetch /api/notifications/me on mount + saat tab kembali fokus +
 * saat event "notifications-updated" dispatched (broadcast / new notif).
 *
 * Optimistic decrement: tap notif di /notifications dispatch
 * "notification-read" → bell langsung kurangi count tanpa refetch.
 * Set juga readIds buat dedup kalau event yg sama fire 2x.
 *
 * Anonymous user: tetap render bell, count selalu 0 (server gak track read).
 */
type NotificationBellProps = {
  compact?: boolean;
};

export function NotificationBell({ compact = false }: NotificationBellProps) {
  const [count, setCount] = useState(0);
  const readIdsRef = useRef<Set<string>>(new Set());

  useEffect(() => {
    let cancelled = false;

    async function fetchCount() {
      try {
        const res = await fetch("/api/notifications/me", { cache: "no-store" });
        if (!res.ok || cancelled) return;
        const data = await res.json();
        if (!cancelled && typeof data.unreadCount === "number") {
          readIdsRef.current.clear();
          setCount(data.unreadCount);
        }
      } catch {
        // silent — bell cuma indicator, gak boleh block render
      }
    }

    void fetchCount();

    function onUpdate() { void fetchCount(); }
    function onRead(e: Event) {
      const detail = (e as CustomEvent<{ id?: string }>).detail;
      const id = detail?.id;
      if (!id) {
        setCount((c) => Math.max(0, c - 1));
        return;
      }
      if (readIdsRef.current.has(id)) return;
      readIdsRef.current.add(id);
      setCount((c) => Math.max(0, c - 1));
    }
    window.addEventListener("notifications-updated", onUpdate);
    window.addEventListener("notification-read", onRead as EventListener);

    function onVisible() { if (!document.hidden) void fetchCount(); }
    document.addEventListener("visibilitychange", onVisible);

    return () => {
      cancelled = true;
      window.removeEventListener("notifications-updated", onUpdate);
      window.removeEventListener("notification-read", onRead as EventListener);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, []);

  return (
    <Link
      href="/notifications"
      className={
        compact
          ? "nat-header-action-glass relative flex h-11 w-11 items-center justify-center rounded-full text-slate-600 transition active:scale-95"
          : "relative flex h-9 w-9 items-center justify-center rounded-full text-gray-600 transition hover:bg-gray-100 active:scale-90 xs:h-10 xs:w-10"
      }
      aria-label={count > 0 ? `Notifikasi (${count} belum dibaca)` : "Notifikasi"}
    >
      <IoNotificationsOutline className={compact ? "h-6 w-6" : "h-5 w-5"} aria-hidden="true" />
      {count > 0 && (
        <span
          className={
            compact
              ? "absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-black leading-none text-white ring-2 ring-white"
              : "absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-red-500 text-[10px] font-bold text-white"
          }
        >
          {count > 9 ? "9+" : count}
        </span>
      )}
    </Link>
  );
}
