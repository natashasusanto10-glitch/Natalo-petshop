/**
 * Wrapper TypeScript untuk SwipeBackPlugin (iOS native).
 *
 * Plugin ini mengaktifkan/menonaktifkan iOS edge-swipe gesture yg
 * trigger history.back() di WKWebView (allowsBackForwardNavigationGestures).
 *
 * Saat web non-Capacitor (browser biasa, PWA), semua method jadi no-op
 * silent — tidak crash, tidak melempar.
 */

import { Capacitor, registerPlugin } from "@capacitor/core";

interface SwipeBackPluginContract {
  enable(): Promise<{ enabled: boolean }>;
  disable(): Promise<{ enabled: boolean }>;
  isEnabled(): Promise<{ enabled: boolean }>;
}

// Native plugin handle. Kalau di non-iOS / non-Capacitor, registerPlugin
// return shim object dgn method yg reject saat dipanggil. Kita wrap supaya
// silent no-op.
const NativeSwipeBack = registerPlugin<SwipeBackPluginContract>("SwipeBack");

function isNative(): boolean {
  return Capacitor.isNativePlatform() && Capacitor.getPlatform() === "ios";
}

export const SwipeBack = {
  async enable(): Promise<void> {
    if (!isNative()) return;
    try {
      await NativeSwipeBack.enable();
    } catch {
      // ignore — bridge/webView belum siap, plugin tidak ada, dst.
    }
  },
  async disable(): Promise<void> {
    if (!isNative()) return;
    try {
      await NativeSwipeBack.disable();
    } catch {
      // ignore
    }
  },
  async isEnabled(): Promise<boolean> {
    if (!isNative()) return false;
    try {
      const result = await NativeSwipeBack.isEnabled();
      return Boolean(result?.enabled);
    } catch {
      return false;
    }
  },
};
