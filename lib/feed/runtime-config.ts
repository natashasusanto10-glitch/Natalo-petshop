/**
 * Device + network derived runtime config for the customer feed player.
 *
 * Two knobs:
 *   - getVirtualWindow()   → how many full <video> cards to mount around
 *                            the active one. Low-RAM phones get fewer to
 *                            stay under their JS heap budget.
 *   - getPreloadTier()     → which preload= attribute a card at distance N
 *                            from active should use. WiFi gets aggressive
 *                            ("auto" on next card too); cellular falls back
 *                            to "metadata" / "none" to save bandwidth.
 *
 * Reads run synchronously off `navigator` and are stable for the session.
 * Capacitor WebView exposes the same APIs as Chrome/Safari, so no native
 * plugin call is needed here.
 */

export type PreloadTier = "auto" | "metadata" | "none";

type ConnectionType = "wifi" | "cellular-fast" | "cellular-slow" | "unknown";

type NavigatorWithConnection = Navigator & {
  connection?: {
    effectiveType?: string;
    type?: string;
    saveData?: boolean;
  };
  deviceMemory?: number;
};

/**
 * Max distance from the active card to still mount a full <FeedVideoCard>.
 *   < 2 GB RAM  → 1  (3 cards in DOM)
 *   2–4 GB RAM  → 2  (5 cards in DOM, spec default)
 *   > 4 GB RAM  → 3  (7 cards in DOM, smoother for fast scroll)
 * Falls back to 2 when deviceMemory is unsupported (Safari, older browsers).
 */
export function getVirtualWindow(): number {
  if (typeof navigator === "undefined") return 2;
  const mem = (navigator as NavigatorWithConnection).deviceMemory;
  if (typeof mem !== "number") return 2;
  if (mem < 2) return 1;
  if (mem >= 4) return 3;
  return 2;
}

function getConnectionType(): ConnectionType {
  if (typeof navigator === "undefined") return "unknown";
  const conn = (navigator as NavigatorWithConnection).connection;
  if (!conn) return "unknown";
  // Honor user's data-saver preference globally — pretend it's a slow link.
  if (conn.saveData) return "cellular-slow";

  const effective = (conn.effectiveType ?? "").toLowerCase();
  if (effective === "4g") return "cellular-fast";
  if (effective === "3g" || effective === "2g" || effective === "slow-2g") {
    return "cellular-slow";
  }

  // `type` is more reliable than effectiveType when it's set.
  const type = (conn.type ?? "").toLowerCase();
  if (type === "wifi" || type === "ethernet") return "wifi";
  if (type === "cellular") return "cellular-fast";
  return "unknown";
}

/**
 * Decide the HTML5 video `preload=` value for a card at `distance` cards
 * away from the active one. Reads the current connection synchronously
 * so each render picks the right tier without a useEffect dance.
 */
export function getPreloadTier(distance: number): PreloadTier {
  const conn = getConnectionType();

  if (conn === "cellular-slow") {
    // 3G / data-saver — only fetch the current card, even metadata for
    // neighbours costs noticeable bytes.
    if (distance === 0) return "auto";
    return "none";
  }

  // WiFi, 4G, or unknown — treat aggressively so swipes feel instant
  // like Instagram Reels / TikTok. iOS Capacitor's WKWebView often reports
  // connection as "unknown" so unknown falling back to "metadata" only
  // was breaking pre-buffer on most installs. Bias toward the WiFi tier:
  // current card auto, ±1 cards auto (next swipe is instant), ±2 cards
  // metadata only. ~10 MB pre-buffer on a typical 720p MP4 feed.
  if (distance === 0) return "auto";
  if (distance === 1) return "auto";
  if (distance === 2) return "metadata";
  return "none";
}

/** Exposed for telemetry — same string format the metrics endpoint expects. */
export function describeNetwork(): string {
  return getConnectionType();
}

export function describeDeviceMemory(): number | null {
  if (typeof navigator === "undefined") return null;
  const mem = (navigator as NavigatorWithConnection).deviceMemory;
  return typeof mem === "number" ? mem : null;
}
