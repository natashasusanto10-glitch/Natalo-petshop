/**
 * POST /api/auth/forgot-password
 * Body: { email: string }
 *
 * Selalu return success (anti email enumeration) — kalau email tidak terdaftar,
 * tetap return ok tapi tidak kirim email.
 *
 * Token: 32 byte random hex (256-bit), expire 1 jam.
 * Rate limit: max 3 request per email per jam (anti spam).
 */
import { NextRequest, NextResponse } from "next/server";
import { randomBytes } from "crypto";
import { prisma } from "@/lib/prisma";
import { sendPasswordResetEmail } from "@/lib/email";

const TOKEN_TTL_MS = 60 * 60 * 1000; // 1 jam
const RATE_LIMIT_PER_HOUR = 3;

export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => ({}));
    const email = String(body.email ?? "").trim().toLowerCase();

    if (!email) {
      return NextResponse.json(
        { error: "Email harus diisi." },
        { status: 400 }
      );
    }

    // Cari user (case-insensitive)
    const user = await prisma.user.findFirst({
      where: { email: { equals: email, mode: "insensitive" } },
      select: { id: true, name: true, email: true },
    });

    // Kalau user ada, generate token & kirim email
    if (user && user.email) {
      // Rate limit: berapa request reset dalam 1 jam terakhir?
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
      const recentCount = await prisma.passwordResetToken.count({
        where: { userId: user.id, createdAt: { gte: oneHourAgo } },
      });

      if (recentCount < RATE_LIMIT_PER_HOUR) {
        // Generate token
        const token = randomBytes(32).toString("hex");
        const expiresAt = new Date(Date.now() + TOKEN_TTL_MS);

        await prisma.passwordResetToken.create({
          data: { token, userId: user.id, expiresAt },
        });

        // Kirim email (await tapi error tidak block response)
        await sendPasswordResetEmail({
          to: user.email,
          userName: user.name,
          token,
        });
      } else {
        console.warn(
          `[forgot-password] rate limit hit for user ${user.id} (${recentCount} requests in last hour)`
        );
      }
    }

    // Selalu return success (anti enumeration)
    return NextResponse.json({
      ok: true,
      message:
        "Kalau email terdaftar, kami sudah mengirim link reset ke inbox kamu. Cek email (termasuk folder spam).",
    });
  } catch (error) {
    console.error("[forgot-password] error:", error);
    return NextResponse.json(
      { error: "Terjadi kesalahan. Coba lagi nanti." },
      { status: 500 }
    );
  }
}
