import { NextRequest, NextResponse } from "next/server";
import bcrypt from "bcryptjs";
import { prisma } from "@/lib/prisma";
import {
  ADMIN_SESSION_COOKIE,
  createSessionToken,
  getSessionCookieOptions,
  MEMBER_SESSION_COOKIE,
} from "@/lib/auth";
import { normalizeIndonesianPhone } from "@/lib/phone";
import {
  checkLimit,
  getClientIp,
  getLoginLimiter,
} from "@/lib/rate-limit";

const MAX_VERIFY_ATTEMPTS = 5;

function getPhoneCandidates(phone: string) {
  const digits = phone.replace(/\D/g, "");
  const normalized = normalizeIndonesianPhone(phone);
  const candidates = new Set<string>([phone.trim(), digits, normalized]);

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

/**
 * Verify OTP login via WhatsApp.
 *
 * Body: `{ phone: string, otp: string }`.
 *
 * Behavior:
 * - Cari user by phone (semua varian format Indonesia).
 * - Cari LoginOtp pending terbaru untuk user tsb.
 * - Cek expired, max attempts (5), bcrypt compare hash.
 * - Sukses: mark verifiedAt + buat session token + set cookie.
 * - Return shape mirror dengan /api/auth/member-login supaya Flutter
 *   bisa share parse logic.
 */
export async function POST(request: NextRequest) {
  try {
    const ip = getClientIp(request.headers);
    // Share login limiter dengan password login — kedua jalur sama2 attempt
    // session creation, jadi attacker brute-force satu cara bakal kena kuota
    // gabungan. 10 attempts / 15 menit cukup untuk legit user yang typo OTP.
    const gate = await checkLimit(getLoginLimiter(), `member-login-otp:${ip}`);
    if (!gate.ok) {
      return NextResponse.json(
        { error: "Terlalu banyak percobaan login. Coba lagi nanti." },
        {
          status: 429,
          headers: { "Retry-After": String(gate.retryAfter) },
        },
      );
    }

    const body = await request.json().catch(() => ({}));
    const rawPhone = String(body.phone || "").trim();
    const otp = String(body.otp || "").replace(/\D/g, "");

    if (!rawPhone || !otp) {
      return NextResponse.json(
        { error: "Nomor WhatsApp dan kode OTP wajib diisi." },
        { status: 400 },
      );
    }
    if (otp.length !== 6) {
      return NextResponse.json(
        { error: "Kode OTP harus 6 digit." },
        { status: 400 },
      );
    }

    const phoneCandidates = getPhoneCandidates(rawPhone);
    const user = await prisma.user.findFirst({
      where: { OR: phoneCandidates.map((phone) => ({ phone })) },
    });

    if (!user) {
      // Anti-enumeration: same generic message untuk user tidak ada vs OTP salah.
      return NextResponse.json(
        { error: "Kode OTP salah atau sudah kedaluwarsa." },
        { status: 401 },
      );
    }

    const pending = await prisma.loginOtp.findFirst({
      where: {
        userId: user.id,
        verifiedAt: null,
      },
      orderBy: { createdAt: "desc" },
    });

    if (!pending) {
      return NextResponse.json(
        {
          error:
            "Kode OTP belum diminta atau sudah tidak berlaku. Minta kode baru.",
        },
        { status: 400 },
      );
    }

    if (pending.expiresAt < new Date()) {
      return NextResponse.json(
        { error: "Kode OTP sudah kedaluwarsa. Minta kode baru." },
        { status: 400 },
      );
    }

    if (pending.attempts >= MAX_VERIFY_ATTEMPTS) {
      return NextResponse.json(
        { error: "Terlalu banyak percobaan OTP. Minta kode baru." },
        { status: 429 },
      );
    }

    const validOtp = await bcrypt.compare(otp, pending.otpHash);
    if (!validOtp) {
      await prisma.loginOtp.update({
        where: { id: pending.id },
        data: { attempts: { increment: 1 } },
      });
      return NextResponse.json(
        { error: "Kode OTP salah." },
        { status: 401 },
      );
    }

    // Sukses → mark verified + create session.
    await prisma.loginOtp.update({
      where: { id: pending.id },
      data: { verifiedAt: new Date() },
    });

    const sessionRole = user.role === "ADMIN" ? "ADMIN" : "CUSTOMER";
    const sessionCookie =
      sessionRole === "ADMIN" ? ADMIN_SESSION_COOKIE : MEMBER_SESSION_COOKIE;

    const token = await createSessionToken({
      sub: user.id,
      role: sessionRole,
      name: user.name,
      tv: user.tokenVersion,
    });

    // Return full user profile termasuk profilePhotoUrl + birthDate +
    // createdAt — match member-login route. BUG FIX: sebelumnya hanya
    // 4 field → Flutter memberStore.profile.profilePhotoUrl null setelah
    // OTP login → foto user "hilang" balik ke initial paw icon.
    const response = NextResponse.json({
      ok: true,
      role: sessionRole,
      token,
      user: {
        id: user.id,
        role: sessionRole,
        name: user.name,
        email: user.email,
        phone: user.phone,
        profilePhotoUrl: user.profilePhotoUrl,
        birthDate: user.birthDate?.toISOString() ?? null,
        createdAt: user.createdAt.toISOString(),
      },
    });
    response.cookies.set(
      sessionCookie,
      token,
      getSessionCookieOptions(request),
    );
    return response;
  } catch (error) {
    console.error("[member-login-otp/verify] error:", error);
    return NextResponse.json(
      { error: "Login OTP sedang bermasalah. Coba lagi sebentar." },
      { status: 500 },
    );
  }
}
