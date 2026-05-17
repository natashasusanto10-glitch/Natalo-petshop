/**
 * Device + network derived runtime config for the customer feed player.
 *
 * Knobs yang di-export:
 *   - getVirtualWindow()         → how many full <video> cards to mount around
 *                                  the active one. Low-RAM phones get fewer to
 *                                  stay under their JS heap budget.
 *   - getPreloadTier()           → which preload= attribute a card at distance N
 *                                  from active should use. Network-aware.
 *   - getRecommendedVideoQuality() → 240/480/720/1080 resolution hint untuk
 *                                  player + signed Bunny URL builder.
 *   - useNetworkTier()           → React hook yang re-render saat
 *                                  navigator.connection.effectiveType berubah
 *                                  (user pindah dari WiFi ke 4G, dll).
 *
 * Reads run synchronously off `navigator` dan stabil per session, kecuali
 * dipakai via useNetworkTier yang re-subscribe ke `change` event.
 * Capacitor WebView exposes the same APIs as Chrome/Safari, so no native
 * plugin call is needed here.
 */

import { useEffect, useState } from "react";

export type PreloadTier = "auto" | "metadata" | "none";
export type VideoQuality = 240 | 360 | 480 | 720 | 1080;
export type NetworkTier =
  | "wifi"           // home WiFi or ethernet — aggressive prefetch
  | "cellular-fast"  // 4G/5G — moderate prefetch
  | "cellular-slow"  // 3G/2G/save-data — conservative
  | "offline"
  | "unknown";

type ConnectionType = "wifi" | "cellular-fast" | "cellular-slow" | "unknown";

type NetworkConnection = {
  effectiveType?: string;
  type?: string;
  saveData?: boolean;
  downlink?: number; // Mbps
  rtt?: number; // ms
  addEventListener?: (event: "change", listener: () => void) => void;
  removeEventListener?: (event: "change", listener: () => void) => void;
};

type NavigatorWithConnection = Navigator & {
  connection?: NetworkConnection;
  mozConnection?: NetworkConnection;
  webkitConnection?: NetworkConnection;
  deviceMemory?: number;
  onLine?: boolean;
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

function getConnection(): NetworkConnection | null {
  if (typeof navigator === "undefined") return null;
  const nav = navigator as NavigatorWithConnection;
  // Vendor prefixes legacy — Chrome/Edge/Opera Android pakai `connection`,
  // Firefox/Safari kadang masih `mozConnection`/`webkitConnection`.
  return nav.connection ?? nav.mozConnection ?? nav.webkitConnection ?? null;
}

function getConnectionType(): ConnectionType {
  if (typeof navigator === "undefined") return "unknown";
  const conn = getConnection();
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
 * Tier yang lebih granular dari ConnectionType internal. Tier ini langsung
 * di-pakai oleh komponen UI (decision: pakai HLS adaptive vs MP4 720p,
 * pre-decode thumbnail atau tidak, dst).
 */
export function getNetworkTier(): NetworkTier {
  if (typeof navigator === "undefined") return "unknown";
  const nav = navigator as NavigatorWithConnection;
  if (nav.onLine === false) return "offline";
  const ct = getConnectionType();
  if (ct === "unknown") {
    // iOS WKWebView sering report "unknown" walaupun ada koneksi. Bias
    // ke cellular-fast supaya pengalaman tidak terlalu konservatif.
    return "cellular-fast";
  }
  return ct;
}

/**
 * Rekomendasi resolusi video untuk current network. Bunny support 240/360/
 * 480/720/1080. Lower tier = lebih cepat play, hemat data; higher tier =
 * gambar lebih tajam tapi butuh bandwidth.
 *
 * Threshold dipilih supaya:
 *   - 4G+ Indonesia (~5-15 Mbps real) cukup nyaman di 720p
 *   - WiFi rumah biasa (~20+ Mbps) bisa 1080p kalau ada
 *   - 3G (~1-3 Mbps) drop ke 480p supaya tidak buffer
 *   - save-data mode → 360p, hemat banget
 */
export function getRecommendedVideoQuality(): VideoQuality {
  const conn = getConnection();
  if (conn?.saveData) return 360;
  const tier = getNetworkTier();
  switch (tier) {
    case "wifi":
      // Ada hint downlink? Kalau >10 Mbps, push ke 1080. Default ke 720
      // supaya tidak ngorbankan smoothness scroll di WiFi marginal.
      if (typeof conn?.downlink === "number" && conn.downlink >= 10) {
        return 1080;
      }
      return 720;
    case "cellular-fast":
      return 720;
    case "cellular-slow":
      // RTT-aware tweak: 3G RTT ~300-700ms biasa, kalau >700 likely 2G/edge.
      if (typeof conn?.rtt === "number" && conn.rtt > 700) return 240;
      return 480;
    case "offline":
      // Tidak akan fetch ulang anyway; balikin resolusi terendah supaya
      // cached entries (kalau ada offline cache) prefer low-res.
      return 240;
    case "unknown":
    default:
      return 720;
  }
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

/**
 * React hook yang re-render saat network tier berubah. Useful untuk:
 *   - Auto-pause autoplay saat user drop ke 2G/offline
 *   - Re-render badge "Hemat data" saat saveData toggle
 *   - Switch video quality dynamically
 *
 * Listener pakai navigator.connection 'change' event. Browser yang tidak
 * support (Safari) return initial tier saja, no live updates — acceptable
 * fallback karena tier-nya jarang ber-change dalam 1 session.
 *
 * Online/offline juga di-listen via window event supaya offline state
 * terdeteksi instan (kalau cuma rely ke navigator.connection, kadang
 * stuck di tier sebelumnya).
 */
export function useNetworkTier(): NetworkTier {
  const [tier, setTier] = useState<NetworkTier>(() => getNetworkTier());

  useEffect(() => {
    if (typeof navigator === "undefined") return;
    const conn = getConnection();

    const update = () => setTier(getNetworkTier());

    conn?.addEventListener?.("change", update);
    window.addEventListener("online", update);
    window.addEventListener("offline", update);

    // Initial sync — kalau hook mount saat user sudah offline misalnya.
    update();

    return () => {
      conn?.removeEventListener?.("change", update);
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);

  return tier;
}
