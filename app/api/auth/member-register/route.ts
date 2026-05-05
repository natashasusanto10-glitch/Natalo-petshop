import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { createSessionToken, SESSION_COOKIE_OPTIONS } from "@/lib/auth";
import bcrypt from "bcryptjs";

export async function POST(request: NextRequest) {
  const { name, identifier, password } = await request.json();

  if (!name || !identifier || !password) {
    return NextResponse.json({ error: "Semua field wajib diisi" }, { status: 400 });
  }

  if (password.length < 8) {
    return NextResponse.json({ error: "Password minimal 8 karakter" }, { status: 400 });
  }

  const isEmail = identifier.includes("@");

  const existing = await prisma.user.findFirst({
    where: isEmail ? { email: identifier } : { phone: identifier },
  });

  if (existing) {
    return NextResponse.json({ error: "Email/HP sudah terdaftar" }, { status: 409 });
  }

  const passwordHash = await bcrypt.hash(password, 12);

  const user = await prisma.user.create({
    data: {
      name,
      email: isEmail ? identifier : null,
      phone: isEmail ? null : identifier,
      passwordHash,
      role: "CUSTOMER",
    },
  });

  const token = await createSessionToken({
    sub: user.id,
    role: "CUSTOMER",
    name: user.name,
  });

  const response = NextResponse.json({ ok: true });
  response.cookies.set("session", token, SESSION_COOKIE_OPTIONS);
  return response;
}
