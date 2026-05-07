import { NextRequest, NextResponse } from "next/server";
import { ADMIN_SESSION_COOKIE, createSessionToken, getSessionCookieOptions } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { createHash, timingSafeEqual } from "crypto";

type Bucket = { count: number; resetAt: number };

const buckets = new Map<string, Bucket>();
const MAX_ATTEMPTS = 5;
const WINDOW_MS = 15 * 60_000;

function safeCompare(a: string, b: string) {
  const hash = (s: string) => createHash("sha256").update(s).digest();
  return timingSafeEqual(hash(a), hash(b));
}

function getKey(request: NextRequest) {
  const ip =
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    request.headers.get("x-real-ip") ??
    "unknown";
  return `admin-login:${ip}`;
}

function checkRateLimit(key: string) {
  const now = Date.now();
  const bucket = buckets.get(key);

  if (!bucket || bucket.resetAt < now) {
    buckets.set(key, { count: 0, resetAt: now + WINDOW_MS });
    return { ok: true };
  }

  if (bucket.count >= MAX_ATTEMPTS) {
    return {
      ok: false,
      retryAfter: Math.ceil((bucket.resetAt - now) / 1000),
    };
  }

  return { ok: true };
}

function recordFailure(key: string) {
  const bucket = buckets.get(key);
  if (bucket) bucket.count += 1;
}

export async function POST(request: NextRequest) {
  const rateLimitKey = getKey(request);
  const gate = checkRateLimit(rateLimitKey);
  if (!gate.ok) {
    return NextResponse.json(
      { error: "Terlalu banyak percobaan. Coba lagi nanti." },
      {
        status: 429,
        headers: { "Retry-After": String(gate.retryAfter) },
      }
    );
  }

  const { email, password } = await request.json();
  const identifier = String(email || "").trim();

  const adminEmail = process.env.ADMIN_EMAIL;
  const adminPassword = process.env.ADMIN_PASSWORD;

  if (!adminEmail || !adminPassword) {
    return NextResponse.json({ error: "Admin belum dikonfigurasi di .env" }, { status: 500 });
  }

  const emailOk = safeCompare(identifier, adminEmail);
  const passOk = safeCompare(password ?? "", adminPassword);

  if (!emailOk || !passOk) {
    recordFailure(rateLimitKey);
    return NextResponse.json({ error: "Username/email/no. HP atau password salah" }, { status: 401 });
  }

  const admin = await prisma.user.upsert({
    where: { id: "admin" },
    create: {
      id: "admin",
      name: "Admin",
      email: adminEmail.includes("@") ? adminEmail : null,
      role: "ADMIN",
    },
    update: {
      name: "Admin",
      role: "ADMIN",
      ...(adminEmail.includes("@") ? { email: adminEmail } : {}),
    },
  });

  const token = await createSessionToken({ sub: admin.id, role: "ADMIN", name: admin.name });
  buckets.delete(rateLimitKey);

  const response = NextResponse.json({ ok: true });
  response.cookies.set(ADMIN_SESSION_COOKIE, token, getSessionCookieOptions(request));
  return response;
}
