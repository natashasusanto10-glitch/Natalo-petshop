import { NextRequest, NextResponse } from "next/server";
import { jwtVerify } from "jose";

function getSecret() {
  const s = process.env.SESSION_SECRET;
  if (!s || s.length < 32) return null;
  return new TextEncoder().encode(s);
}

async function getSessionPayload(request: NextRequest) {
  const token = request.cookies.get("session")?.value;
  if (!token) return null;
  const secret = getSecret();
  if (!secret) return null;
  try {
    const { payload } = await jwtVerify(token, secret);
    return payload;
  } catch {
    return null;
  }
}

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (pathname.startsWith("/api/admin")) {
    const session = await getSessionPayload(request);
    if (!session || session.role !== "ADMIN") {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
  }

  if (pathname.startsWith("/admin")) {
    const session = await getSessionPayload(request);

    if (pathname === "/admin/login") {
      if (session?.role === "ADMIN") {
        return NextResponse.redirect(new URL("/admin/dashboard", request.url));
      }
      if (session?.role === "CUSTOMER") {
        return NextResponse.redirect(new URL("/member/dashboard", request.url));
      }
      return NextResponse.next();
    }

    if (!session) {
      return NextResponse.redirect(new URL("/admin/login", request.url));
    }
    if (session.role === "CUSTOMER") {
      return NextResponse.redirect(new URL("/member/dashboard", request.url));
    }
    if (pathname === "/admin") {
      return NextResponse.redirect(new URL("/admin/dashboard", request.url));
    }
  }

  if (pathname.startsWith("/member") || pathname.startsWith("/akun")) {
    const session = await getSessionPayload(request);

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
