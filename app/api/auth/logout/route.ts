import { NextResponse } from "next/server";
import { ADMIN_SESSION_COOKIE, LEGACY_SESSION_COOKIE, MEMBER_SESSION_COOKIE } from "@/lib/auth";

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

  for (const cookieName of cookiesToClear) {
    response.cookies.set(cookieName, "", {
      httpOnly: true,
      path: "/",
      maxAge: 0,
    });
  }
  return response;
}
