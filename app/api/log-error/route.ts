/**
 * POST /api/log-error
 *
 * Sink for client-side error reports (caught by app/error.tsx,
 * app/global-error.tsx, and any future error boundary). Lightweight —
 * no auth, no DB, just console.log so the error surfaces in Vercel
 * function logs / local dev console.
 *
 * Designed as the integration boundary for Sentry / PostHog / Bugsnag
 * etc. Drop the provider SDK in here when one is wired and every error
 * from every error boundary in the app flows through it automatically.
 *
 * Returns 200 on any input so a retry loop on a client crash can never
 * make things worse.
 */

import { NextRequest, NextResponse } from "next/server";

export const dynamic = "force-dynamic";

type ErrorReport = {
  message?: unknown;
  digest?: unknown;
  stack?: unknown;
  url?: unknown;
  userAgent?: unknown;
  source?: unknown; // "error" | "global-error" | "boundary" | custom
  context?: unknown;
};

function str(value: unknown, limit = 4000): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.length > limit ? `${trimmed.slice(0, limit - 1)}…` : trimmed;
}

export async function POST(request: NextRequest) {
  try {
    const raw = (await request.json().catch(() => null)) as ErrorReport | null;
    if (!raw) return NextResponse.json({ ok: false }, { status: 200 });

    const normalized = {
      message: str(raw.message, 500) ?? "(no message)",
      digest: str(raw.digest, 200),
      stack: str(raw.stack, 4000),
      url: str(raw.url, 500),
      userAgent: str(raw.userAgent, 300),
      source: str(raw.source, 50) ?? "unknown",
      context: typeof raw.context === "object" ? raw.context : undefined,
      ip: request.headers.get("x-forwarded-for") ?? request.headers.get("x-real-ip") ?? null,
      at: new Date().toISOString(),
    };

    // TODO: forward to Sentry / PostHog / Bugsnag here.
    // eslint-disable-next-line no-console
    console.error("[client-error]", normalized);

    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json({ ok: false }, { status: 200 });
  }
}
