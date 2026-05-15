/**
 * POST /api/feed/metrics
 *
 * Receives per-card playback telemetry from the customer feed
 * (useVideoMetrics hook). Right now it just acknowledges and logs to the
 * server console — wire this to an analytics provider (Mixpanel /
 * Amplitude / PostHog / DB table) when one is available. The endpoint
 * boundary stays the same, so the client code never needs to change.
 *
 * Body shape (all fields optional; defensive validation, never 500 the
 * caller):
 *   {
 *     postId: string,
 *     canPlayMs: number,
 *     firstFrameMs: number,
 *     bufferEvents: number,
 *     totalBufferMs: number,
 *     watchMs: number,
 *     videoDurationSec: number | null,
 *     network: "wifi" | "cellular-fast" | "cellular-slow" | "unknown",
 *     deviceMemory: number | null,
 *   }
 *
 * No CSRF guard: sendBeacon can't attach our same-origin headers and the
 * payload is non-mutating telemetry. No auth required either — anonymous
 * playback stats are still useful, and a real analytics provider would
 * fingerprint users their own way.
 */

import { NextRequest, NextResponse } from "next/server";

export const dynamic = "force-dynamic";

type IncomingMetrics = {
  postId?: unknown;
  canPlayMs?: unknown;
  firstFrameMs?: unknown;
  bufferEvents?: unknown;
  totalBufferMs?: unknown;
  watchMs?: unknown;
  videoDurationSec?: unknown;
  network?: unknown;
  deviceMemory?: unknown;
};

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

export async function POST(request: NextRequest) {
  try {
    const raw = (await request.json().catch(() => null)) as IncomingMetrics | null;
    if (!raw || typeof raw.postId !== "string" || !raw.postId) {
      return NextResponse.json({ ok: false }, { status: 200 });
    }

    const normalized = {
      postId: raw.postId,
      canPlayMs: num(raw.canPlayMs),
      firstFrameMs: num(raw.firstFrameMs),
      bufferEvents: num(raw.bufferEvents),
      totalBufferMs: num(raw.totalBufferMs),
      watchMs: num(raw.watchMs),
      videoDurationSec: num(raw.videoDurationSec),
      network: typeof raw.network === "string" ? raw.network : "unknown",
      deviceMemory: num(raw.deviceMemory),
      // Smoothness signal as defined in the spec: zero buffer events AND
      // canPlay landed under the 2s budget. Useful for an at-a-glance %
      // smooth-playback metric in a dashboard later.
      isSmooth:
        (raw.bufferEvents === 0 || raw.bufferEvents === undefined) &&
        typeof raw.canPlayMs === "number" &&
        raw.canPlayMs < 2000,
    };

    // TODO: send to analytics provider here. Until then, log so the metric
    // is visible in Vercel function logs / local dev console.
    // eslint-disable-next-line no-console
    console.info("[feed-metrics]", normalized);

    return NextResponse.json({ ok: true });
  } catch {
    // Never 500 a telemetry beacon — would just create retry storms.
    return NextResponse.json({ ok: false }, { status: 200 });
  }
}
