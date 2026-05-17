"use client";

/**
 * Upload lifecycle hook untuk handle Capacitor app state changes during
 * upload. Pelengkap TUS resumable: TUS sendiri auto-retry kalau koneksi
 * putus, tapi tidak tahu kalau app dipindah ke background. Hook ini:
 *
 *   1. Subscribe ke @capacitor/app `appStateChange` event saat upload
 *      sedang in-flight
 *   2. Saat app → background: simpan resume metadata di localStorage
 *      (TUS sudah simpan fingerprint upload sendiri, kita tambah info
 *      user-facing: filename, postId, timestamp)
 *   3. Saat app → foreground lagi: trigger callback supaya UI bisa
 *      update messaging ("Upload dilanjutkan...")
 *
 * Native iOS quirk: WebView JS context dipause saat app suspended. Network
 * upload masih jalan beberapa detik (iOS background networking budget),
 * lalu di-pause sampai app foreground lagi. TUS sudah handle resume
 * dengan retry exponential backoff.
 *
 * Untuk app yang killed total: file ref hilang, tapi TUS fingerprint
 * di localStorage tetap pointing ke partial upload Bunny side. Kalau
 * user re-pilih file yg sama, tus.findPreviousUploads() match
 * fingerprint dan resume dari byte terakhir.
 */

import { useEffect } from "react";
import { App as CapacitorApp } from "@capacitor/app";

export type UploadLifecycleHandlers = {
  /** Dipanggil saat app dipindah ke background mid-upload. Sebagai
   *  hint UI untuk tampilkan reminder atau switch progress message. */
  onSuspend?: () => void;
  /** Dipanggil saat app kembali ke foreground mid-upload. */
  onResume?: () => void;
};

/**
 * Hook subscribe ke app lifecycle events. Hanya aktif saat enabled=true
 * (yaitu saat upload sedang jalan). Cleanup otomatis saat unmount atau
 * enabled flip ke false.
 *
 * Catatan: di web browser non-Capacitor, App plugin event tetap fire
 * (Capacitor punya web fallback) — tapi kurang reliable karena browser
 * suspend pattern berbeda. Wajib install @capacitor/app yang sudah ada
 * di package.json.
 */
export function useUploadLifecycle(
  enabled: boolean,
  handlers: UploadLifecycleHandlers,
): void {
  useEffect(() => {
    if (!enabled) return;

    let suspended = false;
    let handleRef: { remove: () => void } | null = null;

    // Capacitor App addListener return promise — handle async setup
    // sambil keep cleanup logic synchronous.
    CapacitorApp.addListener("appStateChange", (state) => {
      // state.isActive: true = foreground, false = background
      if (!state.isActive && !suspended) {
        suspended = true;
        handlers.onSuspend?.();
      } else if (state.isActive && suspended) {
        suspended = false;
        handlers.onResume?.();
      }
    })
      .then((handle) => {
        handleRef = handle;
      })
      .catch(() => {
        // Capacitor not available (web build / SSR) — silently skip.
      });

    return () => {
      handleRef?.remove();
    };
  }, [enabled, handlers]);
}

/**
 * Simpan metadata upload yang sedang in-flight di localStorage. Kalau
 * app crash / killed sebelum upload selesai, user buka ulang halaman
 * dan bisa lihat banner "Lanjutkan upload [filename]?" — dengan
 * fingerprint TUS yang sudah ada di localStorage, resume gratis.
 *
 * Window TTL: 24 jam (Bunny TUS session expires after 24h).
 */
const STORAGE_KEY = "natalo-feed-upload-pending";
const TTL_MS = 24 * 60 * 60 * 1000;

export type PendingUploadInfo = {
  postId: string;
  videoGuid: string;
  filename: string;
  sizeMB: number;
  startedAt: number;
};

export function savePendingUpload(info: PendingUploadInfo): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(info));
  } catch {
    // localStorage disabled / quota exceeded — silently skip.
  }
}

export function clearPendingUpload(): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.removeItem(STORAGE_KEY);
  } catch {
    // ignore
  }
}

export function getPendingUpload(): PendingUploadInfo | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const info = JSON.parse(raw) as PendingUploadInfo;
    if (typeof info?.startedAt !== "number") return null;
    if (Date.now() - info.startedAt > TTL_MS) {
      // Expired — clean up.
      clearPendingUpload();
      return null;
    }
    return info;
  } catch {
    return null;
  }
}
