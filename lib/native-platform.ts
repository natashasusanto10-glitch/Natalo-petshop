/**
 * Deteksi apakah app sedang berjalan di dalam Capacitor native WebView
 * (TestFlight .ipa / Android APK). Capacitor inject `window.Capacitor`
 * runtime global saat app dibungkus native shell.
 *
 * Browser biasa (Chrome, Safari, Firefox) + PWA install dari browser
 * (Add to Home Screen) tidak punya `window.Capacitor` → return false.
 */
export function isCapacitorNative(): boolean {
  if (typeof window === "undefined") return false;
  // @ts-expect-error — runtime global, no type
  const cap = window.Capacitor;
  if (!cap) return false;
  try {
    return typeof cap.isNativePlatform === "function" && cap.isNativePlatform();
  } catch {
    return false;
  }
}
