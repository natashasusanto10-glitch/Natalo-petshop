# Persisted Rate Limiter — Implemented via Upstash Redis

**Status:** ✅ Resolved — sudah migrate ke Upstash Redis via `lib/rate-limit.ts`.

**Implementation summary:**
- `lib/rate-limit.ts` — helper dengan graceful fallback kalau env vars belum di-set
- `getLoginLimiter()` — sliding window 10 attempts / 15 min (member-login + admin-login)
- `getOtpLimiter()` — sliding window 5 attempts / 10 min (register OTP + forgot-password)
- `forgot-password` juga punya layer DB-based per-user limit (3/jam) di atas IP-based limit

**Env vars (set di Vercel):**
```
UPSTASH_REDIS_REST_URL=https://xxxxx.upstash.io
UPSTASH_REDIS_REST_TOKEN=AaaaXXXXX...
```

Kalau env vars tidak di-set, limiter fallback ke no-op (allow all) supaya dev local tidak block.

---

## Original Brief (historical, for reference)

**Original status:** Pending — butuh provisioning external store (Upstash Redis / Vercel KV / Postgres row).

**Affected endpoints (currently in-memory rate limit via module-level `Map`):**

| Endpoint | File | Limit |
|---|---|---|
| Member login | `app/api/auth/member-login/route.ts` | 10 attempts / 15 min per IP |
| Admin login | `app/api/auth/admin-login/route.ts` | 10 attempts / 15 min per IP |
| Member register OTP | `app/api/auth/member-register/route.ts` | 5 OTP requests / 10 min per IP+email+phone |
| Forgot password | `app/api/auth/forgot-password/route.ts` | Similar pattern |

## Why current in-memory limit is broken in production

Vercel serverless functions punya **memory per-instance**. Setiap cold start atau new instance = fresh `Map`. Akibatnya:

1. **Attacker bypass mudah:** Vercel load balancer routes requests round-robin ke multiple instances. Attacker yang hit endpoint 100x dalam 1 menit → bisa terdistribusi ke 5+ instances → setiap instance lihat ≤20 attempts (di bawah threshold 10 dengan margin).
2. **Limit reset di cold start:** Instance idle 5 menit → di-recycle → buckets `Map` lost → attacker tinggal tunggu sebentar.
3. **Tidak ada cross-region awareness:** Vercel deploy ke multiple edge regions, masing-masing isolated.

## Recommended fix — Upstash Redis (paling cepat setup)

### Setup

1. [upstash.com](https://upstash.com) → Sign in (free tier: 10K commands/day)
2. Create new **Redis database** (region: pilih yang dekat Vercel deploy, mis. `ap-southeast-1` untuk Singapore)
3. Copy **REST URL** + **REST TOKEN** dari dashboard
4. Set di Vercel env:
   ```
   UPSTASH_REDIS_REST_URL=https://xxxxx.upstash.io
   UPSTASH_REDIS_REST_TOKEN=AaaaXXXXX...
   ```

### Code

```bash
npm install @upstash/redis @upstash/ratelimit
```

Create `lib/rate-limit.ts`:

```ts
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

const redis = Redis.fromEnv();

export const loginRateLimit = new Ratelimit({
  redis,
  limiter: Ratelimit.slidingWindow(10, "15 m"),
  prefix: "rate:login",
});

export const otpRateLimit = new Ratelimit({
  redis,
  limiter: Ratelimit.slidingWindow(5, "10 m"),
  prefix: "rate:otp",
});

export async function checkLimit(
  limiter: Ratelimit,
  identifier: string,
): Promise<{ ok: true } | { ok: false; retryAfter: number }> {
  const result = await limiter.limit(identifier);
  if (result.success) return { ok: true };
  const retryAfter = Math.ceil((result.reset - Date.now()) / 1000);
  return { ok: false, retryAfter };
}
```

Replace di setiap auth endpoint:

```ts
// SEBELUM:
const gate = checkRateLimit(request);
if (!gate.ok) return NextResponse.json(...);

// SESUDAH:
const ip = request.headers.get("x-forwarded-for")?.split(",")[0] ?? "unknown";
const gate = await checkLimit(loginRateLimit, ip);
if (!gate.ok) return NextResponse.json(
  { error: "Terlalu banyak percobaan" },
  { status: 429, headers: { "Retry-After": String(gate.retryAfter) } }
);
```

## Alternative — Vercel KV (sama-sama redis-based, integrasi lebih native)

Setup via Vercel dashboard:
1. Project Settings → Storage → Connect Database → **KV**
2. Auto-add `KV_REST_API_URL` + `KV_REST_API_TOKEN` env vars
3. `npm install @vercel/kv` lalu pakai pattern serupa Upstash

Pricing: $0 untuk 256MB storage + 30K commands/month (free tier).

## Alternative — Postgres row-based (no new infra)

Pakai existing Prisma DB:

```prisma
model RateLimit {
  key      String   @id
  count    Int      @default(1)
  resetAt  DateTime
  @@index([resetAt])
}
```

```ts
async function checkLimit(key: string, max: number, windowMs: number) {
  const now = new Date();
  const expiresAt = new Date(now.getTime() + windowMs);
  const row = await prisma.rateLimit.upsert({
    where: { key },
    create: { key, count: 1, resetAt: expiresAt },
    update: {}, // baca current state
  });
  if (row.resetAt < now) {
    // Window expired, reset
    await prisma.rateLimit.update({
      where: { key },
      data: { count: 1, resetAt: expiresAt },
    });
    return { ok: true };
  }
  if (row.count >= max) {
    return { ok: false, retryAfter: Math.ceil((row.resetAt.getTime() - now.getTime()) / 1000) };
  }
  await prisma.rateLimit.update({
    where: { key },
    data: { count: { increment: 1 } },
  });
  return { ok: true };
}
```

Trade-off: DB write tiap auth attempt, sedikit slower. Tapi tidak butuh infra baru. Cleanup expired rows via Prisma cron atau migration:

```sql
DELETE FROM "RateLimit" WHERE "resetAt" < NOW() - INTERVAL '1 hour';
```

## Decision

Rekomendasi: **Upstash Redis** (paling fast + cheap untuk free tier). Setup 10 menit.

Buka issue/task untuk implementation saat ada bandwidth.
