"use client";

import { useCallback, useSyncExternalStore } from "react";

const UNREAD_INTERVAL_MS = 30_000;

type Snapshot = {
  loggedIn: boolean | null;
  chatEnabled: boolean;
  unread: number;
};

// Satu sumber data untuk semua pemakai hook di halaman yang sama.
// Chat dianggap aktif sampai setelan menyatakan `chatEnabled: false`.
let snapshot: Snapshot = { loggedIn: null, chatEnabled: true, unread: 0 };
const SERVER_SNAPSHOT: Snapshot = { loggedIn: null, chatEnabled: true, unread: 0 };

const listeners = new Set<() => void>();
let unreadSubscribers = 0; // pemakai yang butuh angka belum dibaca
let ready = false; // masuk akun DAN chat aktif
let loaded = false; // auth/me + config sudah dimuat sekali
let loading: Promise<void> | null = null;
let timer: number | null = null;
let attached = false;

function setSnapshot(next: Partial<Snapshot>) {
  const merged = { ...snapshot, ...next };
  if (
    merged.loggedIn === snapshot.loggedIn &&
    merged.chatEnabled === snapshot.chatEnabled &&
    merged.unread === snapshot.unread
  ) {
    return;
  }
  snapshot = merged;
  listeners.forEach((l) => l());
}

async function fetchUnread() {
  if (!ready || unreadSubscribers === 0) return;
  try {
    const res = await fetch("/api/chat/unread", { cache: "no-store", credentials: "same-origin" });
    if (!res.ok) return;
    const json = (await res.json()) as { unreadForCustomer?: number };
    if (typeof json.unreadForCustomer === "number") setSnapshot({ unread: json.unreadForCustomer });
  } catch {
    /* diam saja; dicoba lagi pada putaran berikutnya */
  }
}

function loadAll(): Promise<void> {
  if (loading) return loading;
  loading = (async () => {
    try {
      const [meRes, cfgRes] = await Promise.all([
        fetch("/api/auth/me", { cache: "no-store", credentials: "same-origin" }),
        fetch("/api/chat/config", { cache: "no-store", credentials: "same-origin" }),
      ]);
      const me = meRes.ok ? ((await meRes.json().catch(() => null)) as { id?: string } | null) : null;
      const cfg = cfgRes.ok ? ((await cfgRes.json().catch(() => null)) as { chatEnabled?: boolean } | null) : null;
      const isIn = Boolean(me?.id);
      const enabled = cfg?.chatEnabled !== false;
      ready = isIn && enabled;
      loaded = true;
      setSnapshot({ loggedIn: isIn, chatEnabled: enabled, ...(ready ? {} : { unread: 0 }) });
      await fetchUnread();
    } catch {
      ready = false;
      setSnapshot({ loggedIn: snapshot.loggedIn ?? false });
    } finally {
      loading = null;
    }
  })();
  return loading;
}

function onAuth() {
  void loadAll();
}
function onRead() {
  void fetchUnread();
}
function onVisible() {
  if (document.visibilityState === "visible") void fetchUnread();
}

function startTimer() {
  if (timer !== null || unreadSubscribers === 0) return;
  timer = window.setInterval(() => {
    if (document.visibilityState === "visible") void fetchUnread();
  }, UNREAD_INTERVAL_MS);
}

function stopTimer() {
  if (timer !== null) {
    window.clearInterval(timer);
    timer = null;
  }
}

function attach() {
  if (attached) return;
  attached = true;
  window.addEventListener("auth-updated", onAuth);
  window.addEventListener("chat-read", onRead);
  document.addEventListener("visibilitychange", onVisible);
}

function detach() {
  if (!attached) return;
  attached = false;
  window.removeEventListener("auth-updated", onAuth);
  window.removeEventListener("chat-read", onRead);
  document.removeEventListener("visibilitychange", onVisible);
}

function subscribeStore(withUnread: boolean, listener: () => void) {
  listeners.add(listener);
  if (withUnread) unreadSubscribers += 1;
  attach();
  if (!loaded) void loadAll();
  else if (withUnread && unreadSubscribers === 1) void fetchUnread();
  if (withUnread) startTimer();
  return () => {
    listeners.delete(listener);
    if (withUnread) unreadSubscribers -= 1;
    if (unreadSubscribers === 0) stopTimer();
    if (listeners.size === 0) detach();
  };
}

/**
 * Jumlah pesan toko yang belum dibaca pembeli (untuk titik/angka di tombol chat).
 * Pakai `{ withUnread: false }` bila hanya perlu tahu chat aktif atau tidak.
 */
export function useChatUnread(options?: { withUnread?: boolean }): {
  loggedIn: boolean | null;
  chatEnabled: boolean;
  unread: number;
  refresh(): void;
} {
  const withUnread = options?.withUnread !== false;
  const subscribe = useCallback(
    (listener: () => void) => subscribeStore(withUnread, listener),
    [withUnread],
  );
  const snap = useSyncExternalStore(
    subscribe,
    () => snapshot,
    () => SERVER_SNAPSHOT,
  );

  const refresh = useCallback(() => {
    void loadAll();
  }, []);

  return { loggedIn: snap.loggedIn, chatEnabled: snap.chatEnabled, unread: snap.unread, refresh };
}
