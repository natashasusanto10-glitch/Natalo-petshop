import { SignJWT, jwtVerify } from "jose";
import { cookies } from "next/headers";
import type { NextRequest } from "next/server";

export type SessionPayload = {
  sub: string;
  role: "ADMIN" | "CUSTOMER";
  name: string;
};

export const LEGACY_SESSION_COOKIE = "session";
export const ADMIN_SESSION_COOKIE = "admin_session";
export const MEMBER_SESSION_COOKIE = "member_session";

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

function cookieNameForRole(role: SessionPayload["role"]) {
  return role === "ADMIN" ? ADMIN_SESSION_COOKIE : MEMBER_SESSION_COOKIE;
}

export async function getSession(
  expectedRole?: SessionPayload["role"]
): Promise<SessionPayload | null> {
  const cookieStore = await cookies();

  const cookieNames = expectedRole
    ? [cookieNameForRole(expectedRole), LEGACY_SESSION_COOKIE]
    : [MEMBER_SESSION_COOKIE, ADMIN_SESSION_COOKIE, LEGACY_SESSION_COOKIE];

  for (const cookieName of cookieNames) {
    const token = cookieStore.get(cookieName)?.value;
    if (!token) continue;
    const session = await verifySessionToken(token);
    if (!session) continue;
    if (!expectedRole || session.role === expectedRole) return session;
  }

  return null;
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
