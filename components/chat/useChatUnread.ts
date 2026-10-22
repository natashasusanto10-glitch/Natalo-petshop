"use client";

import { useCallback, useEffect, useRef, useState } from "react";

const UNREAD_INTERVAL_MS = 30_000;

/**
 * Jumlah pesan toko yang belum dibaca pembeli (untuk titik/angka di tombol chat).
 * Tidak melakukan apa-apa bila belum masuk akun atau chat dimatikan.
 */
export function useChatUnread(): {
  loggedIn: boolean | null;
  chatEnabled: boolean;
  unread: number;
  refresh(): void;
} {
  const [loggedIn, setLoggedIn] = useState<boolean | null>(null);
  const [chatEnabled, setChatEnabled] = useState(false);
  const [unread, setUnread] = useState(0);

  const activeRef = useRef(true);
  const readyRef = useRef(false); // masuk akun DAN chat aktif

  const fetchUnread = useCallback(async () => {
    if (!readyRef.current) return;
    try {
      const res = await fetch("/api/chat/unread", { cache: "no-store", credentials: "same-origin" });
      if (!res.ok) return;
      const json = (await res.json()) as { unreadForCustomer?: number };
      if (activeRef.current && typeof json.unreadForCustomer === "number") {
        setUnread(json.unreadForCustomer);
      }
    } catch {
      /* diam saja; dicoba lagi pada putaran berikutnya */
    }
  }, []);

  const loadAll = useCallback(async () => {
    try {
      const [meRes, cfgRes] = await Promise.all([
        fetch("/api/auth/me", { cache: "no-store", credentials: "same-origin" }),
        fetch("/api/chat/config", { cache: "no-store", credentials: "same-origin" }),
      ]);
      if (!activeRef.current) return;
      const me = meRes.ok ? ((await meRes.json().catch(() => null)) as { id?: string } | null) : null;
      const cfg = cfgRes.ok ? ((await cfgRes.json().catch(() => null)) as { chatEnabled?: boolean } | null) : null;
      if (!activeRef.current) return;
      const isIn = Boolean(me?.id);
      // Gagal ambil setelan dianggap aktif; hanya `false` eksplisit yang mematikan.
      const enabled = cfg?.chatEnabled !== false;
      setLoggedIn(isIn);
      setChatEnabled(enabled);
      readyRef.current = isIn && enabled;
      if (readyRef.current) await fetchUnread();
      else setUnread(0);
    } catch {
      if (activeRef.current) {
        readyRef.current = false;
        setLoggedIn((v) => v ?? false);
      }
    }
  }, [fetchUnread]);

  useEffect(() => {
    activeRef.current = true;
    void loadAll();

    const onAuth = () => void loadAll();
    const onRead = () => void fetchUnread();
    const onVisible = () => {
      if (document.visibilityState === "visible") void fetchUnread();
    };
    const timer = window.setInterval(() => {
      if (document.visibilityState === "visible") void fetchUnread();
    }, UNREAD_INTERVAL_MS);

    window.addEventListener("auth-updated", onAuth);
    window.addEventListener("chat-read", onRead);
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      activeRef.current = false;
      window.clearInterval(timer);
      window.removeEventListener("auth-updated", onAuth);
      window.removeEventListener("chat-read", onRead);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [loadAll, fetchUnread]);

  const refresh = useCallback(() => {
    void loadAll();
  }, [loadAll]);

  return { loggedIn, chatEnabled, unread, refresh };
}
