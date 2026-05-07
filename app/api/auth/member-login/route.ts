import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { createSessionToken, getSessionCookieOptions, MEMBER_SESSION_COOKIE } from "@/lib/auth";
import { normalizeIndonesianPhone } from "@/lib/phone";
import bcrypt from "bcryptjs";
import type { User } from "@prisma/client";

type Bucket = { count: number; resetAt: number };
const buckets = new Map<string, Bucket>();
const MAX_ATTEMPTS = 10;
const WINDOW_MS = 15 * 60_000;

function checkRateLimit(request: NextRequest): { ok: boolean; retryAfter?: number } {
  const ip =
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    request.headers.get("x-real-ip") ??
    "unknown";
  const key = `member-login:${ip}`;
  const now = Date.now();
  const bucket = buckets.get(key);
  if (!bucket || bucket.resetAt < now) {
    buckets.set(key, { count: 1, resetAt: now + WINDOW_MS });
    return { ok: true };
  }
  if (bucket.count >= MAX_ATTEMPTS) {
    return { ok: false, retryAfter: Math.ceil((bucket.resetAt - now) / 1000) };
  }
  bucket.count += 1;
  return { ok: true };
}

function getPhoneCandidates(identifier: string) {
  const digits = identifier.replace(/\D/g, "");
  const normalized = normalizeIndonesianPhone(identifier);
  const candidates = new Set([identifier.trim(), digits, normalized]);

  if (normalized.startsWith("0")) {
    candidates.add(`62${normalized.slice(1)}`);
    candidates.add(`+62${normalized.slice(1)}`);
  }

  if (digits.startsWith("62")) {
    candidates.add(`0${digits.slice(2)}`);
    candidates.add(`+${digits}`);
  }

  if (digits.startsWith("8")) {
    candidates.add(`0${digits}`);
    candidates.add(`62${digits}`);
    candidates.add(`+62${digits}`);
  }

  return [...candidates].filter(Boolean);
}

export async function POST(request: NextRequest) {
  const gate = checkRateLimit(request);
  if (!gate.ok) {
    return NextResponse.json(
      { error: "Terlalu banyak percobaan login. Coba lagi nanti." },
      { status: 429, headers: { "Retry-After": String(gate.retryAfter) } }
    );
  }

  const body = await request.json();
  const identifier = String(body.identifier || "").trim();
  const password = String(body.password || "");

  if (!identifier || !password) {
    return NextResponse.json({ error: "Email/HP dan password wajib diisi" }, { status: 400 });
  }

  const isEmail = identifier.includes("@");
  const normalizedIdentifier = identifier.toLowerCase();
  const phoneCandidates = getPhoneCandidates(identifier);
  let user: User | null = await prisma.user.findFirst({
    where: isEmail
      ? { email: { equals: normalizedIdentifier, mode: "insensitive" } }
      : { OR: phoneCandidates.map((phone) => ({ phone })) },
  });

  if (!user && isEmail) {
    const legacyUsers = await prisma.user.findMany({
      where: { email: { not: null }, passwordHash: { not: null } },
    });
    user =
      legacyUsers.find((candidate) => candidate.email?.trim().toLowerCase() === normalizedIdentifier) ??
      null;
  }

  if (!user && !isEmail) {
    const normalizedPhone = normalizeIndonesianPhone(identifier);
    const legacyUsers = await prisma.user.findMany({
      where: { phone: { not: null }, passwordHash: { not: null } },
    });
    user =
      legacyUsers.find((candidate) => normalizeIndonesianPhone(candidate.phone ?? "") === normalizedPhone) ??
      null;
  }

  if (!user || !user.passwordHash) {
    return NextResponse.json({ error: "Akun tidak ditemukan" }, { status: 401 });
  }

  const valid = await bcrypt.compare(password, user.passwordHash);
  if (!valid) {
    return NextResponse.json({ error: "Password salah" }, { status: 401 });
  }

  const token = await createSessionToken({
    sub: user.id,
    role: "CUSTOMER",
    name: user.name,
  });

  const response = NextResponse.json({ ok: true, role: "CUSTOMER" });
  response.cookies.set(MEMBER_SESSION_COOKIE, token, getSessionCookieOptions(request));
  return response;
}
