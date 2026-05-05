import { NextRequest, NextResponse } from "next/server";
import { jwtVerify } from "jose";

function getSecret() {
  const s = process.env.SESSION_SECRET;
  if (!s) return new TextEncoder().encode("fallback-insecure-secret");
  return new TextEncoder().encode(s);
}

async function getSessionPayload(request: NextRequest) {
  const token = request.cookies.get("session")?.value;
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, getSecret());
    return payload;
  } catch {
    return null;
  }
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (pathname.startsWith("/admin")) {
    if (pathname === "/admin/login") return NextResponse.next();

    const session = await getSessionPayload(request);
    if (!session || session.role !== "ADMIN") {
      return NextResponse.redirect(new URL("/admin/login", request.url));
    }
  }

  if (pathname.startsWith("/member")) {
    if (pathname === "/member/login" || pathname === "/member/register") {
      return NextResponse.next();
    }

    const session = await getSessionPayload(request);
    if (!session || session.role !== "CUSTOMER") {
      return NextResponse.redirect(new URL("/member/login", request.url));
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/admin/:path*", "/member/:path*"],
};
