import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { createSessionToken, SESSION_COOKIE_OPTIONS } from "@/lib/auth";
import bcrypt from "bcryptjs";

export async function POST(request: NextRequest) {
  const { identifier, password } = await request.json();

  if (!identifier || !password) {
    return NextResponse.json({ error: "Email/HP dan password wajib diisi" }, { status: 400 });
  }

  const isEmail = identifier.includes("@");
  const user = await prisma.user.findFirst({
    where: isEmail ? { email: identifier } : { phone: identifier },
  });

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

  const response = NextResponse.json({ ok: true });
  response.cookies.set("session", token, SESSION_COOKIE_OPTIONS);
  return response;
}
