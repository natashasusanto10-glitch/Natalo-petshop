import { createHash } from "node:crypto";
import { SignJWT, jwtVerify } from "jose";
import { cookies } from "next/headers";
import type { NextRequest } from "next/server";
import { prisma } from "@/lib/prisma";

export type SessionPayload = {
  sub: string;
  role: "ADMIN" | "CUSTOMER";
  name: string;
  /**
   * Token version. Bumped via `prisma.user.update({ tokenVersion: { increment: 1 } })`
   * to invalidate all JWT yang sudah di-issue (mis. fitur "logout dari semua
   * perangkat"). JWT lama (pre-fitur) yg tidak punya claim ini diperlakukan
   * sebagai tv = 0 (backward-compat dengan default User.tokenVersion).
   */
  tv?: number;
};

export const LEGACY_SESSION_COOKIE = "session";
export const ADMIN_SESSION_COOKIE = "admin_session";
export const MEMBER_SESSION_COOKIE = "member_session";

function getSecret() {
  const s = process.env.SESSION_SECRET;
  if (!s || s.length < 32) {
    throw new Error(
      "SESSION_SECRET wajib di-set (min 32 char). Tidak ada fallback."
    );
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

export async function verifySessionToken(
  token: string
): Promise<SessionPayload | null> {
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

/**
 * SHA-256 fingerprint (hex) of a JWT. Revocation menyimpan HANYA fingerprint
 * ini — bukan JWT mentah — supaya kalau tabel bocor, token asli tidak ikut
 * bocor. Deterministik: JWT yang sama → fingerprint sama.
 */
export function tokenFingerprint(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

/**
 * Ambil bearer token dari header Authorization (case-insensitive). Return null
 * kalau tidak ada / bukan skema Bearer / kosong.
 */
export function extractBearerToken(
  headerValue: string | null | undefined
): string | null {
  if (!headerValue) return null;
  const match = /^bearer\s+(.+)$/i.exec(headerValue.trim());
  if (!match) return null;
  const token = match[1].trim();
  return token.length > 0 ? token : null;
}

/**
 * True kalau [token] sudah di-revoke (fingerprint ada di RevokedToken).
 * Fail-closed: kalau lookup DB gagal, anggap revoked (tolak) — keamanan lebih
 * diutamakan daripada availability untuk validasi sesi.
 */
async function isTokenRevoked(token: string): Promise<boolean> {
  try {
    const row = await prisma.revokedToken.findUnique({
      where: { fingerprint: tokenFingerprint(token) },
      select: { id: true },
    });
    return row != null;
  } catch {
    return true;
  }
}

/**
 * Revoke sebuah token valid: simpan fingerprint + expiry supaya bearer JWT
 * yang masih hidup ikut mati (bukan cuma cookie yang dihapus). Idempotent
 * (upsert). Token yang tidak valid diabaikan. Return true kalau berhasil
 * menandai token valid sebagai revoked.
 */
export async function revokeToken(token: string): Promise<boolean> {
  const session = await verifySessionToken(token);
  if (!session) return false;
  const fingerprint = tokenFingerprint(token);
  // Revocation row cukup hidup selama sisa umur maksimum token (7d). Setelah
  // token kadaluarsa, verifySessionToken sudah menolaknya sendiri.
  const expiresAt = new Date(
    Date.now() + SESSION_COOKIE_OPTIONS.maxAge * 1000
  );
  await prisma.revokedToken.upsert({
    where: { fingerprint },
    create: { fingerprint, expiresAt },
    update: { expiresAt },
  });
  return true;
}

export async function getSession(
  expectedRole?: SessionPayload["role"]
): Promise<SessionPayload | null> {
  const cookieStore = await cookies();

  // Saat expectedRole = CUSTOMER, kita ALSO check admin cookie. Alasan:
  // ADMIN punya privilege superset CUSTOMER (privilege elevation pattern).
  // Admin yang login di Flutter app dengan akun admin tetap bisa akses
  // endpoint member-facing (/api/auth/me, /api/feed/*, /api/cart/*, dll)
  // tanpa di-reject 401 yang memicu auto-logout.
  //
  // Reverse TIDAK berlaku: CUSTOMER ditolak di endpoint ADMIN. Privilege
  // cuma elevate up, tidak down.
  const cookieNames =
    expectedRole == null
      ? [MEMBER_SESSION_COOKIE, ADMIN_SESSION_COOKIE, LEGACY_SESSION_COOKIE]
      : expectedRole === "CUSTOMER"
      ? [MEMBER_SESSION_COOKIE, ADMIN_SESSION_COOKIE, LEGACY_SESSION_COOKIE]
      : [cookieNameForRole(expectedRole), LEGACY_SESSION_COOKIE];

  for (const cookieName of cookieNames) {
    const token = cookieStore.get(cookieName)?.value;
    if (!token) continue;
    const session = await verifySessionToken(token);
    if (!session) continue;
    // Role check: CUSTOMER expectedRole accept BOTH CUSTOMER + ADMIN.
    // Other roles (mis. expectedRole=ADMIN) strict match.
    if (expectedRole) {
      if (expectedRole === "CUSTOMER") {
        if (session.role !== "CUSTOMER" && session.role !== "ADMIN") continue;
      } else if (session.role !== expectedRole) {
        continue;
      }
    }
    if (!(await isTokenVersionCurrent(session))) continue;
    // Bearer JWT yang sudah di-logout/revoke ditolak walau signature + tv
    // masih valid (cookie clearing saja tidak cukup untuk klien bearer).
    if (await isTokenRevoked(token)) continue;
    return session;
  }

  return null;
}

export function isTokenVersionFresh(
  session: Pick<SessionPayload, "tv">,
  currentTokenVersion: number
) {
  return (session.tv ?? 0) >= currentTokenVersion;
}

/**
 * Cek `tv` claim di JWT >= User.tokenVersion di DB.
 * Kalau user pernah klik "logout dari semua perangkat", tokenVersion DB
 * naik 1, JWT lama dgn tv lebih kecil dianggap invalid.
 *
 * Kalau JWT tidak punya tv (issued sebelum fitur ada), default 0 — match
 * default DB (0) sehingga session lama tetap valid sampai user revoke.
 */
async function isTokenVersionCurrent(
  session: SessionPayload
): Promise<boolean> {
  try {
    const user = await prisma.user.findUnique({
      where: { id: session.sub },
      select: { role: true, tokenVersion: true },
    });
    if (!user) return false;
    if (user.role !== session.role) return false;
    return isTokenVersionFresh(session, user.tokenVersion);
  } catch {
    /* Fail-closed: kalau DB unreachable, tolak sesi. Sebelumnya fail-open
       (return true) berarti token yang sudah di-"logout dari semua perangkat"
       tetap diterima selama DB blip — celah keamanan. */
    return false;
  }
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
  const isHttps =
    request?.nextUrl.protocol === "https:" || forwardedProto === "https";

  return {
    ...SESSION_COOKIE_OPTIONS,
    secure: isHttps || SESSION_COOKIE_OPTIONS.secure,
  };
}
