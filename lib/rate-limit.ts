/**
 * Persisted rate limiter via Upstash Redis.
 *
 * Replaces in-memory `Map<string, Bucket>` rate-limiters yang bypass-able
 * di Vercel serverless (setiap instance punya memory sendiri → attacker
 * round-robin bisa multiply effective limit). Lihat docs/RATE_LIMIT_TODO.md
 * untuk context lengkap.
 *
 * Setup: set 2 env vars di Vercel (provisioned via Upstash dashboard):
 *   - UPSTASH_REDIS_REST_URL
 *   - UPSTASH_REDIS_REST_TOKEN
 *
 * Fallback graceful: kalau env vars belum di-set (mis. dev local tanpa
 * Upstash account), `checkLimit()` return `{ ok: true }` selalu — tidak
 * block legitimate dev traffic. Warning di-log sekali.
 *
 * Pattern usage:
 *   import { checkLimit, loginLimiter } from "@/lib/rate-limit";
 *
 *   const ip = getClientIp(request);
 *   const gate = await checkLimit(loginLimiter, `login:${ip}`);
 *   if (!gate.ok) return NextResponse.json(
 *     { error: "Terlalu banyak percobaan" },
 *     { status: 429, headers: { "Retry-After": String(gate.retryAfter) } }
 *   );
 */
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

let warnedNoEnv = false;

function getRedisClient(): Redis | null {
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) {
    if (!warnedNoEnv) {
      warnedNoEnv = true;
      console.warn(
        "[rate-limit] UPSTASH_REDIS_REST_URL / TOKEN belum di-set — fallback ke no-op (semua request lewat). Set 2 env vars di Vercel untuk aktivasi.",
      );
    }
    return null;
  }
  return new Redis({ url, token });
}

// Sliding window 15 menit, 10 attempts.
// Digunakan untuk member-login + admin-login.
let loginLimiterCache: Ratelimit | null = null;
export function getLoginLimiter(): Ratelimit | null {
  if (loginLimiterCache) return loginLimiterCache;
  const redis = getRedisClient();
  if (!redis) return null;
  loginLimiterCache = new Ratelimit({
    redis,
    limiter: Ratelimit.slidingWindow(10, "15 m"),
    prefix: "rate:login",
    analytics: false, // hemat Upstash command quota
  });
  return loginLimiterCache;
}

// Sliding window 10 menit, 5 attempts.
// Digunakan untuk register OTP send + forgot-password.
let otpLimiterCache: Ratelimit | null = null;
export function getOtpLimiter(): Ratelimit | null {
  if (otpLimiterCache) return otpLimiterCache;
  const redis = getRedisClient();
  if (!redis) return null;
  otpLimiterCache = new Ratelimit({
    redis,
    limiter: Ratelimit.slidingWindow(5, "10 m"),
    prefix: "rate:otp",
    analytics: false,
  });
  return otpLimiterCache;
}

// Sliding window 1 menit, 30 calls.
// Digunakan untuk endpoint yang call paid external API (Google Maps Places,
// reverse-geocode). Lebih longgar dari OTP karena UX autocomplete butuh
// banyak call per detik saat user ketik.
let mapsLimiterCache: Ratelimit | null = null;
export function getMapsLimiter(): Ratelimit | null {
  if (mapsLimiterCache) return mapsLimiterCache;
  const redis = getRedisClient();
  if (!redis) return null;
  mapsLimiterCache = new Ratelimit({
    redis,
    limiter: Ratelimit.slidingWindow(30, "1 m"),
    prefix: "rate:maps",
    analytics: false,
  });
  return mapsLimiterCache;
}

// Sliding window 1 jam, 20 calls.
// Digunakan untuk AI product-assistant — cegah OpenAI budget burn dari
// 1 logged-in user yang loop POSTs.
let aiLimiterCache: Ratelimit | null = null;
export function getAiLimiter(): Ratelimit | null {
  if (aiLimiterCache) return aiLimiterCache;
  const redis = getRedisClient();
  if (!redis) return null;
  aiLimiterCache = new Ratelimit({
    redis,
    limiter: Ratelimit.slidingWindow(20, "1 h"),
    prefix: "rate:ai",
    analytics: false,
  });
  return aiLimiterCache;
}

type LimitResult =
  | { ok: true }
  | { ok: false; retryAfter: number };

/**
 * Cek rate limit untuk identifier (mis. IP, IP+email, email+phone).
 * Returns { ok: true } kalau allowed, atau { ok: false, retryAfter }
 * kalau over limit. Fallback ke `{ ok: true }` saat limiter null
 * (env not set) supaya tidak block dev/staging traffic.
 *
 * Limiter param: pass result dari getLoginLimiter() atau getOtpLimiter().
 * Pattern lazy supaya init Redis hanya saat actual request datang.
 */
export async function checkLimit(
  limiter: Ratelimit | null,
  identifier: string,
): Promise<LimitResult> {
  if (!limiter) return { ok: true };
  try {
    const result = await limiter.limit(identifier);
    if (result.success) return { ok: true };
    const retryAfter = Math.max(
      1,
      Math.ceil((result.reset - Date.now()) / 1000),
    );
    return { ok: false, retryAfter };
  } catch (err) {
    // Upstash/network error — fail-open (allow request). Lebih baik
    // miss-limit sekali daripada block legitimate user pas Redis down.
    console.error("[rate-limit] check failed, allowing request:", err);
    return { ok: true };
  }
}

/**
 * Helper untuk extract client IP dari Next.js request headers.
 * Mirror pattern lama di tiap auth route, sekarang centralized.
 */
export function getClientIp(headers: Headers): string {
  const forwarded = headers.get("x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) return first;
  }
  const realIp = headers.get("x-real-ip");
  if (realIp) return realIp;
  return "unknown";
}
