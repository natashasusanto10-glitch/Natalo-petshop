"use client";

import { useEffect, useState } from "react";

/**
 * Offline status banner for PWA and Capacitor builds.
 *
 * Sources:
 * 1. Browser online/offline events for web/PWA fallback.
 * 2. @capacitor/network for native reachability.
 * 3. Periodic native status polling, so the UI recovers even if an event is missed.
 */

type ConnectionState = {
  connected: boolean;
  type?: string;
};

export function NetworkStatusBanner() {
  const [state, setState] = useState<ConnectionState>({ connected: true });
  const [showReconnected, setShowReconnected] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined") return;

    let cancelled = false;
    let unsubscribe: (() => void) | null = null;
    let pollId: number | null = null;
    let reconnectedTimer: number | null = null;

    function showReconnectedBriefly() {
      if (reconnectedTimer) window.clearTimeout(reconnectedTimer);
      setShowReconnected(true);
      reconnectedTimer = window.setTimeout(() => setShowReconnected(false), 2500);
    }

    function applyStatus(next: ConnectionState) {
      setState((prev) => {
        if (next.connected && !prev.connected) {
          showReconnectedBriefly();
        }
        if (!next.connected) {
          if (reconnectedTimer) window.clearTimeout(reconnectedTimer);
          setShowReconnected(false);
        }
        return next;
      });
    }

    function handleOnline() {
      applyStatus({ connected: true });
    }

    function handleOffline() {
      applyStatus({ connected: false, type: "none" });
    }

    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);

    applyStatus({ connected: navigator.onLine });

    (async () => {
      try {
        const { Network } = await import("@capacitor/network");

        async function checkConnection() {
          const status = await Network.getStatus();
          if (!cancelled) {
            applyStatus({ connected: status.connected, type: status.connectionType });
          }
        }

        await checkConnection();

        const handle = await Network.addListener("networkStatusChange", (status) => {
          applyStatus({ connected: status.connected, type: status.connectionType });
        });

        if (cancelled) {
          await handle.remove();
          return;
        }

        pollId = window.setInterval(checkConnection, 15000);
        unsubscribe = () => {
          void handle.remove();
        };
      } catch {
        // Non-Capacitor web build: browser events above remain active.
      }
    })();

    return () => {
      cancelled = true;
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
      if (pollId) window.clearInterval(pollId);
      if (reconnectedTimer) window.clearTimeout(reconnectedTimer);
      unsubscribe?.();
    };
  }, []);

  if (state.connected && !showReconnected) return null;

  return (
    <div
      role="status"
      aria-live="polite"
      className={`fixed inset-x-0 top-0 z-[55] flex items-center justify-center gap-2 px-4 py-2 text-sm font-bold shadow-md transition-all duration-300 ${
        state.connected
          ? "bg-green-500 text-white"
          : "bg-amber-400 text-amber-950"
      }`}
      style={{ paddingTop: "max(0.5rem, env(safe-area-inset-top))" }}
    >
      {state.connected ? (
        <>
          <svg className="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}>
            <path d="M5 12l5 5L20 7" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          <span>Koneksi tersambung kembali</span>
        </>
      ) : (
        <>
          <svg className="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}>
            <path d="M1 1l22 22M16.72 11.06A10.94 10.94 0 0 1 19 12.55M5 12.55a10.94 10.94 0 0 1 5.17-2.39M10.71 5.05A16 16 0 0 1 22.58 9M1.42 9a15.91 15.91 0 0 1 4.7-2.88M8.53 16.11a6 6 0 0 1 6.95 0M12 20h.01" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          <span>Kamu sedang offline - beberapa fitur tidak tersedia</span>
        </>
      )}
    </div>
  );
}
