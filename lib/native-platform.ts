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

/**
 * Deteksi iOS — covers Capacitor iOS app, Mobile Safari, dan iPadOS yang
 * masquerading sebagai Mac (iPadOS 13+ default desktop user agent).
 *
 * Dipakai untuk workaround bug WKWebView iOS yang tidak ada di Android/web,
 * mis. <input capture="environment"> crash di iOS 26 WKWebView sebelum
 * permission prompt sempat tampil.
 */
export function isIOS(): boolean {
  if (typeof navigator === "undefined") return false;
  const ua = navigator.userAgent;
  if (/iPad|iPhone|iPod/.test(ua)) return true;
  // iPadOS 13+ default UA = Mac. Detect via maxTouchPoints (Mac tidak punya touch).
  if (
    navigator.platform === "MacIntel" &&
    typeof navigator.maxTouchPoints === "number" &&
    navigator.maxTouchPoints > 1
  ) {
    return true;
  }
  return false;
}
