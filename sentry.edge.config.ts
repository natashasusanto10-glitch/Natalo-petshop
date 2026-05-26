/**
 * Sentry — edge runtime configuration.
 *
 * Loaded saat code jalan di Edge runtime (middleware.ts, route dengan
 * `export const runtime = "edge"`). Lebih limited dari server config —
 * gak ada Node API, jadi profiling/disk-based feature di-skip.
 *
 * Same env var SENTRY_DSN sebagai gate.
 */
import * as Sentry from "@sentry/nextjs";

const DSN = process.env.SENTRY_DSN || process.env.NEXT_PUBLIC_SENTRY_DSN;

if (DSN) {
  Sentry.init({
    dsn: DSN,
    environment: process.env.VERCEL_ENV || process.env.NODE_ENV || "development",
    tracesSampleRate: 0.1,
    sendDefaultPii: false,
    ignoreErrors: ["AbortError"],
  });
}
