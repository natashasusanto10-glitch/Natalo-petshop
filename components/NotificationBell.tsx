"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

/**
 * Bell icon untuk header — link ke /notifications dgn badge unread count.
 *
 * Polling sederhana: fetch /api/notifications/me on mount + saat event
 * "notifications-updated" dispatched (mis. setelah tap notif → mark read).
 *
 * Anonymous user: tetap render bell (link tetap kerja), tapi unreadCount
 * selalu 0 — server return 0 untuk anonymous karena gak ada track read.
 */
export function NotificationBell() {
  const [count, setCount] = useState(0);

  useEffect(() => {
    let cancelled = false;

    async function fetchCount() {
      try {
        const res = await fetch("/api/notifications/me", { cache: "no-store" });
        if (!res.ok || cancelled) return;
        const data = await res.json();
        if (!cancelled && typeof data.unreadCount === "number") {
          setCount(data.unreadCount);
        }
      } catch {
        // silent — bell cuma indicator, gak boleh block render
      }
    }

    void fetchCount();
    function onUpdate() { void fetchCount(); }
    window.addEventListener("notifications-updated", onUpdate);

    // Refresh saat tab kembali fokus (user switch dari tab lain).
    function onVisible() { if (!document.hidden) void fetchCount(); }
    document.addEventListener("visibilitychange", onVisible);

    return () => {
      cancelled = true;
      window.removeEventListener("notifications-updated", onUpdate);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, []);

  return (
    <Link
      href="/notifications"
      className="relative flex h-9 w-9 items-center justify-center rounded-full text-gray-600 transition hover:bg-gray-100 xs:h-10 xs:w-10"
      aria-label={count > 0 ? `Notifikasi (${count} belum dibaca)` : "Notifikasi"}
    >
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={1.8}
        className="h-5 w-5"
        aria-hidden="true"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          d="M14.857 17.082a23.848 23.848 0 0 0 5.454-1.31A8.967 8.967 0 0 1 18 9.75V9A6 6 0 0 0 6 9v.75a8.967 8.967 0 0 1-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 0 1-5.714 0m5.714 0a3 3 0 1 1-5.714 0"
        />
      </svg>
      {count > 0 && (
        <span className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-red-500 text-[10px] font-bold text-white">
          {count > 9 ? "9+" : count}
        </span>
      )}
    </Link>
  );
}
