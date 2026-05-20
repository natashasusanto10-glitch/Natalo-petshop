import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  createSessionToken,
  getSessionCookieOptions,
  MEMBER_SESSION_COOKIE,
} from "@/lib/auth";
import { normalizeIndonesianPhone } from "@/lib/phone";
import { checkLimit, getClientIp, getLoginLimiter } from "@/lib/rate-limit";
import bcrypt from "bcryptjs";
import type { User } from "@prisma/client";

function getPhoneCandidates(identifier: string) {
  const digits = identifier.replace(/\D/g, "");
  const normalized = normalizeIndonesianPhone(identifier);
  const candidates = new Set([identifier.trim(), digits, normalized]);

  if (normalized.startsWith("0")) {
    candidates.add(`62${normalized.slice(1)}`);
    candidates.add(`+62${normalized.slice(1)}`);
  }

  if (digits.startsWith("62")) {
    candidates.add(`0${digits.slice(2)}`);
    candidates.add(`+${digits}`);
  }

  if (digits.startsWith("8")) {
    candidates.add(`0${digits}`);
    candidates.add(`62${digits}`);
    candidates.add(`+62${digits}`);
  }

  return [...candidates].filter(Boolean);
}

async function verifyPassword(
  password: string,
  passwordHash: string,
  userId: string
) {
  try {
    return await bcrypt.compare(password, passwordHash);
  } catch (error) {
    console.error("[member-login] password compare failed:", { userId, error });
    return false;
  }
}

export async function POST(request: NextRequest) {
  try {
    const ip = getClientIp(request.headers);
    const gate = await checkLimit(getLoginLimiter(), `member-login:${ip}`);
    if (!gate.ok) {
      return NextResponse.json(
        { error: "Terlalu banyak percobaan login. Coba lagi nanti." },
        { status: 429, headers: { "Retry-After": String(gate.retryAfter) } }
      );
    }

    const body = await request.json().catch(() => ({}));
    const identifier = String(body.identifier || "").trim();
    const password = String(body.password || "");

    if (!identifier || !password) {
      return NextResponse.json(
        { error: "Email/HP dan password wajib diisi" },
        { status: 400 }
      );
    }

    const isEmail = identifier.includes("@");
    const normalizedIdentifier = identifier.toLowerCase().trim();
    const phoneCandidates = getPhoneCandidates(identifier);
    // Email: case-insensitive match. Untuk legacy data dgn whitespace di
    // kolom email, kita coba juga raw identifier yang sudah di-trim.
    // Phone: pakai exhaustive candidate list dari getPhoneCandidates.
    // Sebelumnya ada fallback `findMany({ ... }).filter(...)` yang load
    // SEMUA legacy user ke memory tiap login attempt → scale linear.
    // Sekarang full indexed lookup.
    const user: User | null = await prisma.user.findFirst({
      where: isEmail
        ? {
            OR: [
              { email: { equals: normalizedIdentifier, mode: "insensitive" } },
              { email: { equals: identifier.trim(), mode: "insensitive" } },
            ],
          }
        : { OR: phoneCandidates.map((phone) => ({ phone })) },
    });

    if (!user) {
      return NextResponse.json(
        { error: "Akun tidak ditemukan" },
        { status: 401 }
      );
    }

    if (!user.passwordHash) {
      return NextResponse.json(
        {
          error:
            "Akun ini belum punya password member. Gunakan Lupa Password untuk membuat password baru.",
        },
        { status: 401 }
      );
    }

    const valid = await verifyPassword(password, user.passwordHash, user.id);
    if (!valid) {
      return NextResponse.json({ error: "Password salah" }, { status: 401 });
    }

    const token = await createSessionToken({
      sub: user.id,
      role: "CUSTOMER",
      name: user.name,
      tv: user.tokenVersion,
    });

    // Return full user profile termasuk profilePhotoUrl + birthDate +
    // createdAt. BUG FIX: sebelumnya hanya 4 field (id/name/email/phone)
    // → Flutter memberStore.profile.profilePhotoUrl null setelah login
    // → avatar fallback ke initial paw icon (foto user "hilang").
    // Client harus terima full snapshot supaya UI immediately akurat
    // tanpa harus extra GET /api/auth/me.
    const response = NextResponse.json({
      ok: true,
      role: "CUSTOMER",
      token,
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        profilePhotoUrl: user.profilePhotoUrl,
        birthDate: user.birthDate?.toISOString() ?? null,
        createdAt: user.createdAt.toISOString(),
      },
    });
    response.cookies.set(
      MEMBER_SESSION_COOKIE,
      token,
      getSessionCookieOptions(request)
    );
    return response;
  } catch (error) {
    console.error("[member-login] error:", error);
    return NextResponse.json(
      { error: "Login sedang bermasalah. Coba lagi sebentar." },
      { status: 500 }
    );
  }
}
