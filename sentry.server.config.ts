/**
 * Sentry — server runtime (Node.js) configuration.
 *
 * Loaded via `instrumentation.ts` saat Next.js boot di Node.js runtime.
 * Capture error dari:
 *   - API routes (app/api/.../route.ts)
 *   - Server Components (app/.../page.tsx, layout.tsx)
 *   - Server Actions (`use server` functions)
 *   - Middleware (kalau Node runtime)
 *
 * Tidak aktif kalau SENTRY_DSN env var kosong — defensive untuk lokal
 * development supaya tidak spam Sentry quota.
 */
import * as Sentry from "@sentry/nextjs";

const DSN = process.env.SENTRY_DSN || process.env.NEXT_PUBLIC_SENTRY_DSN;

if (DSN) {
  Sentry.init({
    dsn: DSN,
    environment: process.env.VERCEL_ENV || process.env.NODE_ENV || "development",

    // Sample rate untuk transaction tracing — 10% untuk balance signal vs
    // cost. Naikan ke 1.0 kalau lagi debug performance issue tertentu.
    tracesSampleRate: 0.1,

    // Profile slow transactions — set 0 untuk hemat (Sentry profiling cost).
    profilesSampleRate: 0,

    // Skip noise yang gak actionable. Tambah pattern di sini saat ada
    // recurring error yang sudah di-acknowledge tapi gak bisa di-fix.
    ignoreErrors: [
      // Client disconnects mid-request — common di mobile network jelek
      "AbortError",
      "ECONNRESET",
      // Prisma graceful errors yang kita handle pakai response 4xx
      "P2002", // unique constraint
      "P2025", // record not found
    ],

    // Strip PII otomatis dari request (header cookie, body sensitive).
    // Tetap include user.id supaya bisa group error per-user.
    sendDefaultPii: false,

    beforeSend(event) {
      // Defense-in-depth: strip authorization header kalau lolos auto-scrub.
      if (event.request?.headers) {
        delete event.request.headers["authorization"];
        delete event.request.headers["cookie"];
      }
      return event;
    },
  });
}
