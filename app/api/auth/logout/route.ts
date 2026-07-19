import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import {
  ADMIN_SESSION_COOKIE,
  extractBearerToken,
  LEGACY_SESSION_COOKIE,
  MEMBER_SESSION_COOKIE,
  revokeToken,
} from "@/lib/auth";

export async function POST(request: Request) {
  const response = NextResponse.json({ ok: true });
  let scope: "ADMIN" | "CUSTOMER" | "ALL" = "ALL";
  try {
    const body = await request.json();
    if (body?.scope === "ADMIN" || body?.scope === "CUSTOMER") scope = body.scope;
  } catch {
    // Older callers without a JSON body log out of both sessions.
  }

  const cookiesToClear =
    scope === "ADMIN"
      ? [ADMIN_SESSION_COOKIE, LEGACY_SESSION_COOKIE]
      : scope === "CUSTOMER"
      ? [MEMBER_SESSION_COOKIE, LEGACY_SESSION_COOKIE]
      : [MEMBER_SESSION_COOKIE, ADMIN_SESSION_COOKIE, LEGACY_SESSION_COOKIE];

  // Revoke the presented token so a still-valid bearer JWT (mobile clients)
  // dies too — clearing the cookie alone left the JWT usable. Best-effort:
  // any failure here must NOT block cookie clearing below.
  try {
    const cookieStore = await cookies();
    const bearer = extractBearerToken(request.headers.get("authorization"));
    const cookieToken =
      cookieStore.get(MEMBER_SESSION_COOKIE)?.value ??
      cookieStore.get(ADMIN_SESSION_COOKIE)?.value ??
      cookieStore.get(LEGACY_SESSION_COOKIE)?.value ??
      null;
    const token = bearer ?? cookieToken;
    if (token) await revokeToken(token);
  } catch {
    // Ignore — logout must always succeed at clearing cookies.
  }

  for (const cookieName of cookiesToClear) {
    response.cookies.set(cookieName, "", {
      httpOnly: true,
      path: "/",
      maxAge: 0,
    });
  }
  return response;
}
