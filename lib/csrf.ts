/**
 * CSRF guard — verify Origin header pada state-changing requests.
 *
 * Session cookies pakai `sameSite: "lax"` (lib/auth.ts) yang melindungi
 * cross-site POST top-level navigation, TAPI tidak cover same-site
 * sub-domain attacks, embedded iframes di domain trust-bound, atau
 * extension calls.
 *
 * Defense-in-depth: tolak request POST/PUT/PATCH/DELETE yang Origin-nya
 * tidak match domain allowlist.
 *
 * Pattern usage di API route:
 *
 *   import { assertSameOrigin } from "@/lib/csrf";
 *
 *   export async function POST(req: NextRequest) {
 *     const reject = assertSameOrigin(req);
 *     if (reject) return reject;
 *     // ... handler logic ...
 *   }
 *
 * Native Capacitor app (iOS/Android WebView) origin biasanya
 * `capacitor://localhost` atau `https://localhost` — di-allowlist via
 * CAPACITOR_ORIGIN regex.
 */
import { NextRequest, NextResponse } from "next/server";

const PRODUCTION_HOSTS = [
  "natalo-petshop.vercel.app",
  "www.natalopetshop.com",
  "natalopetshop.com",
];

// Capacitor iOS / Android WebView origins. Capacitor inject origin
// `capacitor://localhost` (iOS) atau `https://localhost` (Android).
const CAPACITOR_ORIGINS = ["capacitor://localhost", "https://localhost"];

function originHostAllowed(origin: string): boolean {
  if (!origin) return false;
  if (CAPACITOR_ORIGINS.includes(origin)) return true;

  try {
    const url = new URL(origin);
    // Production hosts (exact match or subdomain) + localhost untuk dev.
    if (url.hostname === "localhost" || url.hostname === "127.0.0.1") {
      return true;
    }
    return PRODUCTION_HOSTS.some(
      (host) => url.hostname === host || url.hostname.endsWith(`.${host}`),
    );
  } catch {
    return false;
  }
}

/**
 * Reject kalau Origin header tidak match allowlist.
 * Return NextResponse 403 untuk reject, atau `null` untuk lanjut.
 *
 * Kalau Origin header missing (mis. same-origin GET dari browser), allow —
 * GET request seharusnya idempotent, dan POST modern selalu kirim Origin.
 */
export function assertSameOrigin(req: NextRequest): NextResponse | null {
  // Skip enforcement di dev untuk testing dgn curl/Postman.
  if (process.env.NODE_ENV !== "production") return null;

  const origin = req.headers.get("origin");
  if (!origin) {
    // No Origin header — common di tools like curl/native fetch without origin.
    // Untuk strict mode: bisa di-reject. Sekarang allow biar tidak break
    // mobile app yg kadang strip Origin di Capacitor lama.
    return null;
  }

  if (originHostAllowed(origin)) return null;

  return NextResponse.json(
    { error: "Forbidden — invalid Origin" },
    { status: 403 },
  );
}
