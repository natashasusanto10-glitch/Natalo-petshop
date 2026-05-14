import { NextRequest, NextResponse } from "next/server";
import {
  ADMIN_SESSION_COOKIE,
  createSessionToken,
  getSessionCookieOptions,
} from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { checkLimit, getClientIp, getLoginLimiter } from "@/lib/rate-limit";
import { createHash, timingSafeEqual } from "crypto";

function safeCompare(a: string, b: string) {
  const hash = (s: string) => createHash("sha256").update(s).digest();
  return timingSafeEqual(hash(a), hash(b));
}

export async function POST(request: NextRequest) {
  const ip = getClientIp(request.headers);
  const gate = await checkLimit(getLoginLimiter(), `admin-login:${ip}`);
  if (!gate.ok) {
    return NextResponse.json(
      { error: "Terlalu banyak percobaan. Coba lagi nanti." },
      {
        status: 429,
        headers: { "Retry-After": String(gate.retryAfter) },
      },
    );
  }

  const { email, password } = await request.json();
  const identifier = String(email || "").trim();

  const adminEmail = process.env.ADMIN_EMAIL;
  const adminPassword = process.env.ADMIN_PASSWORD;

  if (!adminEmail || !adminPassword) {
    return NextResponse.json(
      { error: "Admin belum dikonfigurasi di .env" },
      { status: 500 },
    );
  }

  const emailOk = safeCompare(identifier, adminEmail);
  const passOk = safeCompare(password ?? "", adminPassword);

  if (!emailOk || !passOk) {
    // Sliding-window di Upstash sudah counter setiap call ke limiter,
    // jadi tidak perlu manual recordFailure (limit auto-track per request).
    return NextResponse.json(
      { error: "Username/email/no. HP atau password salah" },
      { status: 401 },
    );
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

  const token = await createSessionToken({
    sub: admin.id,
    role: "ADMIN",
    name: admin.name,
    tv: admin.tokenVersion,
  });

  const response = NextResponse.json({ ok: true });
  response.cookies.set(
    ADMIN_SESSION_COOKIE,
    token,
    getSessionCookieOptions(request)
  );
  return response;
}
