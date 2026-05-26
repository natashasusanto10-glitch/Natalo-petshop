/**
 * Sentry — client (browser) instrumentation.
 *
 * Auto-loaded oleh Next.js 16+ saat browser bundle boot. Capture error
 * dari:
 *   - React render errors (yang bubble ke error/global-error boundary)
 *   - Window onerror / unhandledrejection
 *   - Manual `Sentry.captureException()` di client component
 *
 * NEXT_PUBLIC_SENTRY_DSN dipakai karena env var ini di-inline ke bundle
 * client (SENTRY_DSN tanpa NEXT_PUBLIC prefix tidak accessible di browser).
 */
import * as Sentry from "@sentry/nextjs";

const DSN = process.env.NEXT_PUBLIC_SENTRY_DSN;

if (DSN) {
  Sentry.init({
    dsn: DSN,
    environment: process.env.NEXT_PUBLIC_VERCEL_ENV || "development",

    // Replay session — record DOM mutation + clicks saat error terjadi.
    // 0.1 sample = 10% session. Mask all input by default (privacy).
    // Naikan ke 1.0 kalau lagi diagnose UX bug spesifik.
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0.1,

    integrations: [
      Sentry.replayIntegration({
        maskAllText: true,
        maskAllInputs: true,
        blockAllMedia: true,
      }),
    ],

    tracesSampleRate: 0.1,
    sendDefaultPii: false,

    ignoreErrors: [
      // Browser extension noise
      "Non-Error promise rejection captured",
      "ResizeObserver loop limit exceeded",
      "ResizeObserver loop completed with undelivered notifications",
      // User network issues
      "Failed to fetch",
      "NetworkError",
      "Load failed",
      // Capacitor / WebView bridge timing (in-app browser)
      "Capacitor",
    ],
  });
}

// Export router-transition hook untuk Next.js capture navigation timing.
export const onRouterTransitionStart = Sentry.captureRouterTransitionStart;
