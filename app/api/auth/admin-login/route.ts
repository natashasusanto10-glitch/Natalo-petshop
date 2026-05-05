import { NextRequest, NextResponse } from "next/server";
import { createSessionToken, SESSION_COOKIE_OPTIONS } from "@/lib/auth";
import { timingSafeEqual } from "crypto";

function safeCompare(a: string, b: string) {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

export async function POST(request: NextRequest) {
  const { email, password } = await request.json();

  const adminEmail = process.env.ADMIN_EMAIL;
  const adminPassword = process.env.ADMIN_PASSWORD;

  if (!adminEmail || !adminPassword) {
    return NextResponse.json({ error: "Admin belum dikonfigurasi di .env" }, { status: 500 });
  }

  const emailOk = safeCompare(email ?? "", adminEmail);
  const passOk = safeCompare(password ?? "", adminPassword);

  if (!emailOk || !passOk) {
    return NextResponse.json({ error: "Email atau password salah" }, { status: 401 });
  }

  const token = await createSessionToken({ sub: "admin", role: "ADMIN", name: "Admin" });

  const response = NextResponse.json({ ok: true });
  response.cookies.set("session", token, SESSION_COOKIE_OPTIONS);
  return response;
}
