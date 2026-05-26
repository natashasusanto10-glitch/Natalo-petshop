"use client";

import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";
import Link from "next/link";

export default function ErrorPage({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error(error);
    // Direct Sentry capture — preserve native stack + grouping. No-op kalau
    // SDK gak ke-init (NEXT_PUBLIC_SENTRY_DSN kosong di lokal dev).
    try {
      Sentry.captureException(error, {
        tags: { source: "error-boundary", origin: "react-boundary" },
        contexts: { react: { digest: error.digest } },
      });
    } catch {
      // Telemetry never crashes recovery UI.
    }
    // Fire-and-forget error report — sendBeacon so the request survives
    // even if the page is mid-unmount when the boundary fires. Endpoint
    // is the integration point for Sentry / PostHog later.
    try {
      const body = JSON.stringify({
        source: "error-boundary",
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
      } else {
        void fetch("/api/log-error", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body,
          keepalive: true,
        }).catch(() => {});
      }
    } catch {
      // Telemetry must never break the recovery UI itself.
    }
  }, [error]);

  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
      <span className="text-6xl">😿</span>
      <h1 className="mt-4 text-2xl font-black text-gray-900">Terjadi Kesalahan</h1>
      <p className="mt-2 max-w-sm text-sm text-gray-500">
        Ada sesuatu yang tidak beres. Coba muat ulang halaman atau kembali ke beranda.
      </p>
      <div className="mt-6 flex flex-wrap justify-center gap-3">
        <button
          onClick={reset}
          className="rounded-full bg-blue-500 px-6 py-3 text-sm font-bold text-white transition hover:bg-blue-600"
        >
          Coba Lagi
        </button>
        <Link
          href="/"
          className="rounded-full border border-gray-200 px-6 py-3 text-sm font-bold text-gray-700 transition hover:border-blue-300 hover:text-blue-500"
        >
          Kembali ke Beranda
        </Link>
      </div>
    </div>
  );
}
