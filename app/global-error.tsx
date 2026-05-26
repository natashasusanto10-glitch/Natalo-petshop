"use client";

import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  console.error("[GlobalError]", error);

  // Fire-and-forget error report. Runs in effect (not render) so that a
  // re-render during recovery doesn't spam duplicate beacons.
  useEffect(() => {
    // Direct capture ke Sentry — lebih cepat + retain native stack vs
    // synthetic reconstruction di /api/log-error. No-op kalau SDK gak
    // ke-init (DSN env kosong).
    try {
      Sentry.captureException(error, {
        tags: { source: "global-error", origin: "react-boundary" },
        contexts: {
          react: { digest: error.digest },
        },
      });
    } catch {
      // Never break the recovery screen itself.
    }

    // Backup: kirim beacon ke /api/log-error supaya tetap muncul di
    // Vercel function logs walau client Sentry SDK gagal load.
    try {
      const body = JSON.stringify({
        source: "global-error",
        message: error.message,
        digest: error.digest,
        stack: error.stack,
        url: typeof window !== "undefined" ? window.location.href : null,
        userAgent: typeof navigator !== "undefined" ? navigator.userAgent : null,
      });
      if (typeof navigator !== "undefined" && navigator.sendBeacon) {
        navigator.sendBeacon(
          "/api/log-error",
          new Blob([body], { type: "application/json" }),
        );
      }
    } catch {
      // Never break the recovery screen itself.
    }
  }, [error]);

  return (
    <html lang="id">
      <body>
        <div
          style={{
            alignItems: "center",
            background: "#f9f9f7",
            color: "#111111",
            display: "flex",
            fontFamily: "system-ui, -apple-system, sans-serif",
            justifyContent: "center",
            minHeight: "100vh",
            padding: "20px",
          }}
        >
          <div style={{ maxWidth: 400, textAlign: "center", width: "100%" }}>
            <div aria-hidden="true" style={{ fontSize: 48, marginBottom: 16 }}>
              🐾
            </div>
            <h1
              style={{
                fontSize: 20,
                fontWeight: 500,
                margin: "0 0 8px",
              }}
            >
              Website sedang bermasalah
            </h1>
            <p
              style={{
                color: "#777777",
                fontSize: 14,
                lineHeight: 1.6,
                margin: "0 0 20px",
              }}
            >
              Maaf atas ketidaknyamanannya. Silakan coba lagi dalam beberapa
              saat.
            </p>
            <button
              onClick={() => reset()}
              style={{
                background: "#1E5FBF",
                border: "none",
                borderRadius: 8,
                color: "white",
                cursor: "pointer",
                fontSize: 14,
                fontWeight: 500,
                padding: "10px 24px",
              }}
              type="button"
            >
              Coba Lagi
            </button>
            {error.digest && (
              <p
                style={{
                  color: "#aaaaaa",
                  fontFamily: "monospace",
                  fontSize: 12,
                  marginTop: 20,
                }}
              >
                Error ID: {error.digest}
              </p>
            )}
          </div>
        </div>
      </body>
    </html>
  );
}
