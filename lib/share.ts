/**
 * Universal share utility — abstract antar Capacitor native, Web Share API, dan
 * clipboard fallback. Pakai ini di mana saja butuh share content (URL produk,
 * order tracking, voucher, dll).
 *
 * Priority:
 * 1. iOS native (TestFlight/.ipa) → @capacitor/share — trigger UIActivityView
 *    dengan semua app installed (WhatsApp, Instagram, Mail, AirDrop, Notes, dll)
 * 2. Web modern (PWA Safari, Chrome Android) → navigator.share — Web Share API
 *    yang kasih native share sheet juga
 * 3. Browser tanpa Web Share API (desktop Chrome, Firefox) → clipboard copy +
 *    toast notification "Link disalin"
 */

export type ShareData = {
  title?: string;
  text?: string;
  url?: string;
  /** Optional dialog title untuk Android (no-op di iOS) */
  dialogTitle?: string;
};

export type ShareResult =
  | { method: "native"; activity?: string }
  | { method: "web-share" }
  | { method: "clipboard" }
  | { method: "cancelled" }
  | { method: "failed"; error: unknown };

export async function shareContent(data: ShareData): Promise<ShareResult> {
  // 1. Try Capacitor Share plugin (iOS/Android native)
  try {
    const { Share } = await import("@capacitor/share");
    const canShare = await Share.canShare();
    if (canShare.value) {
      const result = await Share.share({
        title: data.title,
        text: data.text,
        url: data.url,
        dialogTitle: data.dialogTitle,
      });
      // result.activityType ada saat user pilih app (iOS), null kalau cancel
      return { method: "native", activity: result.activityType };
    }
  } catch (err) {
    // Plugin not available (web non-Capacitor) atau user cancelled
    if (err && typeof err === "object" && "message" in err) {
      const msg = String((err as Error).message);
      if (msg.toLowerCase().includes("cancel")) {
        return { method: "cancelled" };
      }
    }
    // Fall through ke Web Share API
  }

  // 2. Try Web Share API (PWA Safari iOS, Chrome Android, etc.)
  if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
    try {
      await navigator.share({
        title: data.title,
        text: data.text,
        url: data.url,
      });
      return { method: "web-share" };
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") {
        return { method: "cancelled" };
      }
      // Fall through ke clipboard
    }
  }

  // 3. Fallback: copy URL ke clipboard
  if (data.url && typeof navigator !== "undefined" && navigator.clipboard) {
    try {
      await navigator.clipboard.writeText(data.url);
      return { method: "clipboard" };
    } catch (err) {
      return { method: "failed", error: err };
    }
  }

  return { method: "failed", error: new Error("No share method available") };
}
