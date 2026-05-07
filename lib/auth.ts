import { SignJWT, jwtVerify } from "jose";
import { cookies } from "next/headers";
import type { NextRequest } from "next/server";

export type SessionPayload = {
  sub: string;
  role: "ADMIN" | "CUSTOMER";
  name: string;
};

function getSecret() {
  const s = process.env.SESSION_SECRET;
  if (!s || s.length < 32) {
    throw new Error("SESSION_SECRET wajib di-set (min 32 char). Tidak ada fallback.");
  }
  return new TextEncoder().encode(s);
}

export async function createSessionToken(payload: SessionPayload) {
  return new SignJWT(payload as unknown as Record<string, unknown>)
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("7d")
    .sign(getSecret());
}

export async function verifySessionToken(token: string): Promise<SessionPayload | null> {
  const s = process.env.SESSION_SECRET;
  if (!s || s.length < 32) return null;

  try {
    const { payload } = await jwtVerify(token, new TextEncoder().encode(s));
    return payload as unknown as SessionPayload;
  } catch {
    return null;
  }
}

export async function getSession(): Promise<SessionPayload | null> {
  const cookieStore = await cookies();
  const token = cookieStore.get("session")?.value;
  if (!token) return null;
  return verifySessionToken(token);
}

export const SESSION_COOKIE_OPTIONS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax" as const,
  path: "/",
  maxAge: 60 * 60 * 24 * 7,
};

export function getSessionCookieOptions(request?: NextRequest) {
  const forwardedProto = request?.headers.get("x-forwarded-proto");
  const isHttps = request?.nextUrl.protocol === "https:" || forwardedProto === "https";

  return {
    ...SESSION_COOKIE_OPTIONS,
    secure: isHttps || SESSION_COOKIE_OPTIONS.secure,
  };
}
