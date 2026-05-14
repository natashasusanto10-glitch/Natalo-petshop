/**
 * POST /api/auth/reset-password
 * Body: { token: string, password: string }
 *
 * Validasi:
 *   - Token ada, belum dipakai (usedAt=null), belum expired
 *   - Password min 8 char
 * Side effect:
 *   - Update user.passwordHash
 *   - Set token.usedAt = now (anti reuse)
 *   - Hapus semua token lain milik user (clean up)
 */
import { NextRequest, NextResponse } from "next/server";
import bcrypt from "bcryptjs";
import { prisma } from "@/lib/prisma";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => ({}));
    const token = String(body.token ?? "").trim();
    const password = String(body.password ?? "");

    if (!token) {
      return NextResponse.json(
        { error: "Token tidak valid." },
        { status: 400 }
      );
    }
    if (password.length < 8) {
      return NextResponse.json(
        { error: "Password minimal 8 karakter." },
        { status: 400 }
      );
    }

    const tokenRecord = await prisma.passwordResetToken.findUnique({
      where: { token },
    });

    if (!tokenRecord) {
      return NextResponse.json(
        { error: "Token tidak valid atau sudah pernah dipakai." },
        { status: 400 }
      );
    }
    if (tokenRecord.usedAt) {
      return NextResponse.json(
        { error: "Link reset sudah pernah dipakai. Minta link baru." },
        { status: 400 }
      );
    }
    if (tokenRecord.expiresAt < new Date()) {
      return NextResponse.json(
        { error: "Link reset sudah kedaluwarsa. Minta link baru." },
        { status: 400 }
      );
    }

    const passwordHash = await bcrypt.hash(password, 10);

    await prisma.$transaction([
      // Update password user + bump tokenVersion → force-logout semua sesi
      // aktif di device lain (mis. device attacker yang sebelumnya sempat
      // login dengan password lama).
      prisma.user.update({
        where: { id: tokenRecord.userId },
        data: {
          passwordHash,
          tokenVersion: { increment: 1 },
        },
      }),
      // Mark token as used
      prisma.passwordResetToken.update({
        where: { id: tokenRecord.id },
        data: { usedAt: new Date() },
      }),
      // Hapus token lain milik user (kalau request multiple)
      prisma.passwordResetToken.deleteMany({
        where: {
          userId: tokenRecord.userId,
          id: { not: tokenRecord.id },
          usedAt: null,
        },
      }),
    ]);

    return NextResponse.json({
      ok: true,
      message: "Password berhasil diubah. Silakan login dengan password baru.",
    });
  } catch (error) {
    console.error("[reset-password] error:", error);
    return NextResponse.json(
      { error: "Terjadi kesalahan. Coba lagi nanti." },
      { status: 500 }
    );
  }
}
