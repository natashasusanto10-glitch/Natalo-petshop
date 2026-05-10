/**
 * Universal external link opener — abstract antar Capacitor in-app browser
 * (SafariViewController di iOS), Web window.open, dan native deep-link
 * (mis. wa.me, mailto:, tel:).
 *
 * Pakai ini untuk semua link external (target="_blank") di app supaya
 * di iOS native (TestFlight/.ipa), user gak kicked out ke Safari, tapi
 * stay di app dengan SafariViewController preview (UX kayak Instagram,
 * Twitter, TikTok).
 *
 * Special URLs yang TETAP buka native handler (BUKAN in-app browser):
 * - wa.me / api.whatsapp.com → WhatsApp app
 * - mailto: → Mail app
 * - tel: → Phone app
 * - sms: → Messages app
 * - maps:, geo: → Maps app
 *
 * Reasoning: native app handler kasih experience yang lebih baik dari in-app
 * web view (mis. WhatsApp lebih cepat buka chat dari deep link daripada
 * load whatsapp.com).
 */

const NATIVE_SCHEMES = ["mailto:", "tel:", "sms:", "maps:", "geo:", "facetime:", "whatsapp:"];
const NATIVE_HOSTS = [
  "wa.me",
  "api.whatsapp.com",
  "chat.whatsapp.com",
  "maps.apple.com",
  "maps.google.com",
];

function isNativeHandlerUrl(url: string): boolean {
  if (NATIVE_SCHEMES.some((scheme) => url.toLowerCase().startsWith(scheme))) {
    return true;
  }
  try {
    const parsed = new URL(url);
    return NATIVE_HOSTS.some((host) => parsed.hostname === host || parsed.hostname.endsWith(`.${host}`));
  } catch {
    return false;
  }
}

export type OpenLinkOptions = {
  /** Toolbar color di iOS Capacitor Browser. Default brand blue. */
  toolbarColor?: string;
  /** Window name target untuk web window.open. Default "_blank" */
  windowName?: string;
  /**
   * Force buka di in-app browser walaupun URL match native handler.
   * Jarang dipakai — biasanya kita mau native handler buka (mis. wa.me → WhatsApp app).
   */
  forceInApp?: boolean;
};

/**
 * Buka link external. Behavior:
 * - URL native (wa.me, mailto:, tel:, dll) → biarin OS native handler (browser
 *   web standard akan launch WhatsApp/Mail app).
 * - URL web biasa (https://...) di iOS native (.ipa) → @capacitor/browser
 *   SafariViewController in-app.
 * - Web/PWA → window.open(_blank).
 */
export async function openExternalLink(url: string, opts: OpenLinkOptions = {}): Promise<void> {
  const { toolbarColor = "#1E5FBF", windowName = "_blank", forceInApp = false } = opts;

  // Native handler URLs (wa.me, mailto, tel) — skip in-app browser, biar OS launch native app
  if (!forceInApp && isNativeHandlerUrl(url)) {
    if (typeof window !== "undefined") {
      window.location.href = url; // iOS WebView akan delegate ke native app handler
    }
    return;
  }

  // Try Capacitor Browser (iOS native in-app SafariViewController)
  try {
    const { Browser } = await import("@capacitor/browser");
    await Browser.open({
      url,
      toolbarColor,
      // iOS-specific: use SafariViewController vs full browser
      presentationStyle: "popover",
    });
    return;
  } catch {
    // Plugin not available (web non-Capacitor) → fallback ke window.open
  }

  // Fallback: standard window.open
  if (typeof window !== "undefined") {
    window.open(url, windowName, "noopener,noreferrer");
  }
}

/**
 * Click handler factory untuk dipakai di onClick={...}.
 * Auto preventDefault supaya gak double-trigger native href behavior.
 */
export function externalLinkHandler(url: string, opts?: OpenLinkOptions) {
  return (e: React.MouseEvent | React.PointerEvent) => {
    e.preventDefault();
    e.stopPropagation();
    void openExternalLink(url, opts);
  };
}
