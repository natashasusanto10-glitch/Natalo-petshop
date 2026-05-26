/**
 * Next.js Instrumentation entry — root file yang di-load sekali per runtime
 * saat Next.js boot. Pattern resmi Next.js 13.4+ untuk wiring observability
 * tools (Sentry, OpenTelemetry, dst).
 *
 * Per-runtime config dynamic-import biar tidak ke-bundle module yang gak
 * compatible (mis. server SDK punya Node API yang gak ada di edge).
 *
 * Reference: https://nextjs.org/docs/app/building-your-application/optimizing/instrumentation
 */

export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    await import("./sentry.server.config");
  }
  if (process.env.NEXT_RUNTIME === "edge") {
    await import("./sentry.edge.config");
  }
}

/**
 * Hook dipanggil Next.js saat ada error di nested React server component
 * boundary. Forward ke Sentry supaya muncul di issue feed.
 */
export async function onRequestError(
  err: unknown,
  request: {
    path: string;
    method: string;
    headers: { [key: string]: string };
  },
  context: {
    routerKind: "Pages Router" | "App Router";
    routePath: string;
    routeType: "render" | "route" | "action" | "middleware";
    renderSource:
      | "react-server-components"
      | "react-server-components-payload"
      | "server-rendering";
    revalidateReason: "on-demand" | "stale" | undefined;
    renderType: "dynamic" | "dynamic-resume";
  },
) {
  const Sentry = await import("@sentry/nextjs");
  Sentry.captureRequestError(err, request, context);
}
