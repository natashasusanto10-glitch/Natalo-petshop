import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { normalizeIndonesianPhone } from "@/lib/phone";
import bcrypt from "bcryptjs";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const name = String(body.name || "").trim();
  const email = String(body.email || "").trim().toLowerCase();
  const phone = normalizeIndonesianPhone(String(body.phone || ""));
  const password = String(body.password || "");
  const confirmPassword = String(body.confirmPassword || "");

  if (!name || !email || !phone || !password || !confirmPassword) {
    return NextResponse.json({ error: "Semua field wajib diisi" }, { status: 400 });
  }

  if (!email.includes("@")) {
    return NextResponse.json({ error: "Format email tidak valid" }, { status: 400 });
  }

  if (phone.length < 8 || !phone.startsWith("0")) {
    return NextResponse.json({ error: "Nomor handphone tidak valid" }, { status: 400 });
  }

  if (password.length < 8) {
    return NextResponse.json({ error: "Password minimal 8 karakter" }, { status: 400 });
  }

  if (password !== confirmPassword) {
    return NextResponse.json({ error: "Konfirmasi password tidak sama" }, { status: 400 });
  }

  const existing = await prisma.user.findFirst({
    where: {
      OR: [
        { email },
        { phone },
      ],
    },
  });

  if (existing) {
    return NextResponse.json({ error: "Email atau no. handphone sudah terdaftar" }, { status: 409 });
  }

  const passwordHash = await bcrypt.hash(password, 12);

  await prisma.user.create({
    data: {
      name,
      email,
      phone,
      passwordHash,
      role: "CUSTOMER",
    },
  });

  return NextResponse.json({ ok: true });
}
