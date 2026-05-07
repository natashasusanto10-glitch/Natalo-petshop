import { NextRequest, NextResponse } from "next/server";
import { jwtVerify } from "jose";

const LEGACY_SESSION_COOKIE = "session";
const ADMIN_SESSION_COOKIE = "admin_session";
const MEMBER_SESSION_COOKIE = "member_session";

function getSecret() {
  const s = process.env.SESSION_SECRET;
  if (!s || s.length < 32) return null;
  return new TextEncoder().encode(s);
}

async function getSessionPayload(
  request: NextRequest,
  expectedRole?: "ADMIN" | "CUSTOMER"
) {
  const cookieNames = expectedRole === "ADMIN"
    ? [ADMIN_SESSION_COOKIE, LEGACY_SESSION_COOKIE]
    : expectedRole === "CUSTOMER"
    ? [MEMBER_SESSION_COOKIE, LEGACY_SESSION_COOKIE]
    : [MEMBER_SESSION_COOKIE, ADMIN_SESSION_COOKIE, LEGACY_SESSION_COOKIE];
  const secret = getSecret();
  if (!secret) return null;

  for (const cookieName of cookieNames) {
    const token = request.cookies.get(cookieName)?.value;
    if (!token) continue;
    try {
      const { payload } = await jwtVerify(token, secret);
      if (!expectedRole || payload.role === expectedRole) return payload;
    } catch {
      // Try next candidate cookie.
    }
  }

  return null;
}

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (pathname.startsWith("/api/admin")) {
    const session = await getSessionPayload(request, "ADMIN");
    if (!session || session.role !== "ADMIN") {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
  }

  if (pathname.startsWith("/admin")) {
    const session = await getSessionPayload(request, "ADMIN");

    if (pathname === "/admin/login") {
      if (session?.role === "ADMIN") {
        return NextResponse.redirect(new URL("/admin/dashboard", request.url));
      }
      return NextResponse.next();
    }

    if (!session) {
      return NextResponse.redirect(new URL("/admin/login", request.url));
    }
    if (pathname === "/admin") {
      return NextResponse.redirect(new URL("/admin/dashboard", request.url));
    }
  }

  if (pathname.startsWith("/member") || pathname.startsWith("/akun")) {
    const session = await getSessionPayload(request, "CUSTOMER");

    // Halaman login & register: kalau sudah login → redirect ke dashboard
    if (pathname === "/member/login" || pathname === "/member/register") {
      if (session?.role === "CUSTOMER") {
        return NextResponse.redirect(new URL("/member/dashboard", request.url));
      }
      return NextResponse.next();
    }

    // Halaman forgot/reset password: PUBLIC — tidak perlu session.
    // (User yang lupa password jelas tidak bisa login dulu untuk akses ini.)
    if (
      pathname === "/member/forgot-password" ||
      pathname === "/member/reset-password"
    ) {
      return NextResponse.next();
    }

    // Sisanya wajib login sebagai CUSTOMER
    if (!session || session.role !== "CUSTOMER") {
      return NextResponse.redirect(new URL("/member/login", request.url));
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/admin/:path*", "/api/admin/:path*", "/member/:path*", "/akun/:path*"],
};
