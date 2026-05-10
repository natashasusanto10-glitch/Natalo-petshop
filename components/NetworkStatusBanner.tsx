"use client";

import { useEffect, useState } from "react";

/**
 * Banner offline status — tampil di top of screen saat hp gak ada koneksi.
 * Auto-hide saat reconnect.
 *
 * Listen ke 2 source:
 * 1. @capacitor/network (iOS native): paling akurat, native reachability check
 * 2. window.addEventListener("online" | "offline"): browser/PWA fallback
 *
 * Penting untuk daerah dengan 4G spotty. User dapat feedback visual yang
 * jelas kenapa request mereka gagal.
 */

type ConnectionState = {
  connected: boolean;
  type?: string; // "wifi" | "cellular" | "none" | "unknown"
};

export function NetworkStatusBanner() {
  const [state, setState] = useState<ConnectionState>({ connected: true });
  const [showReconnected, setShowReconnected] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined") return;

    let unsubscribe: (() => void) | null = null;

    // 1. Browser online/offline events (works for PWA/web)
    function handleOnline() {
      setState((prev) => {
        if (!prev.connected) {
          // Was offline, now back online — show "Reconnected" briefly
          setShowReconnected(true);
          setTimeout(() => setShowReconnected(false), 2500);
        }
        return { connected: true };
      });
    }
    function handleOffline() {
      setState({ connected: false });
      setShowReconnected(false);
    }

    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);

    // Initial state from browser
    setState({ connected: navigator.onLine });

    // 2. Capacitor Network plugin (iOS native — more accurate)
    (async () => {
      try {
        const { Network } = await import("@capacitor/network");

        const status = await Network.getStatus();
        setState({ connected: status.connected, type: status.connectionType });

        const handle = await Network.addListener("networkStatusChange", (status) => {
          setState((prev) => {
            if (status.connected && !prev.connected) {
              setShowReconnected(true);
              setTimeout(() => setShowReconnected(false), 2500);
            }
            return { connected: status.connected, type: status.connectionType };
          });
        });

        unsubscribe = () => handle.remove();
      } catch {
        // Web / non-Capacitor — fallback to browser events only
      }
    })();

    return () => {
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
      unsubscribe?.();
    };
  }, []);

  // Render: banner offline (kuning) atau "Reconnected" (hijau brief)
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
          <span>Kamu sedang offline — beberapa fitur tidak tersedia</span>
        </>
      )}
    </div>
  );
}
