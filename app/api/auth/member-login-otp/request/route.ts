import { NextRequest, NextResponse } from "next/server";
import { randomInt } from "crypto";
import bcrypt from "bcryptjs";
import { prisma } from "@/lib/prisma";
import { normalizeIndonesianPhone } from "@/lib/phone";
import { sendCustomMessage } from "@/lib/whatsapp";
import {
  checkLimit,
  getClientIp,
  getOtpLimiter,
} from "@/lib/rate-limit";

const OTP_EXPIRES_MS = 5 * 60_000;

function generateOtp() {
  return String(randomInt(100000, 1000000));
}

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

async function sendOtpViaWhatsapp({
  phone,
  name,
  otp,
}: {
  phone: string;
  name: string;
  otp: string;
}) {
  const message = [
    `Kode OTP login *Natalo Petshop*: ${otp}`,
    "",
    "Kode berlaku 5 menit. Jangan bagikan kode ini ke siapa pun.",
    "Kalau bukan kamu yang minta, abaikan pesan ini.",
  ].join("\n");

  if (!process.env.FONNTE_TOKEN?.trim()) {
    console.log("\n" + "=".repeat(60));
    console.log("[DEV MODE] OTP WhatsApp login member");
    console.log("=".repeat(60));
    console.log(`To     : ${phone}`);
    console.log(`Halo   : ${name}`);
    console.log(`OTP    : ${otp}`);
    console.log(`Expires: 5 menit`);
    console.log("=".repeat(60));
    console.log("Set FONNTE_TOKEN di .env untuk kirim WhatsApp beneran.\n");
    return { ok: true };
  }

  return sendCustomMessage(phone, message);
}

/**
 * Request OTP login via WhatsApp.
 *
 * Body: `{ phone: string }`.
 *
 * Behavior:
 * - Cari user by phone (semua varian format Indonesia).
 * - Selalu return success 200 supaya tidak bocor "user terdaftar atau tidak"
 *   (anti-enumeration). Tapi kalau user tidak ada, OTP tidak benar-benar dibuat.
 * - Rate limit: 5 request per 10 menit per IP+phone (sama dengan register OTP).
 * - OTP 6 digit, expired 5 menit (lebih pendek dari register karena user
 *   yang request login biasanya online — tidak perlu buffer email yang lambat).
 */
export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => ({}));
    const rawPhone = String(body.phone || "").trim();

    if (!rawPhone) {
      return NextResponse.json(
        { error: "Nomor WhatsApp wajib diisi." },
        { status: 400 },
      );
    }

    const ip = getClientIp(request.headers);
    const rateKey = `login-otp:${ip}:${rawPhone}`;
    const gate = await checkLimit(getOtpLimiter(), rateKey);
    if (!gate.ok) {
      return NextResponse.json(
        { error: "Terlalu banyak permintaan OTP. Coba lagi nanti." },
        {
          status: 429,
          headers: { "Retry-After": String(gate.retryAfter) },
        },
      );
    }

    const phoneCandidates = getPhoneCandidates(rawPhone);
    const user = await prisma.user.findFirst({
      where: { OR: phoneCandidates.map((phone) => ({ phone })) },
      select: { id: true, name: true, phone: true },
    });

    // Anti-enumeration: kalau user tidak ada, tetap return 200 dengan delay
    // ringan. Tidak benar-benar bikin OTP atau kirim WA.
    if (!user || !user.phone) {
      // Random jitter 200-600ms supaya tidak ada timing leak.
      await new Promise((resolve) =>
        setTimeout(resolve, 200 + Math.random() * 400),
      );
      return NextResponse.json({
        ok: true,
        message:
          "Jika nomor terdaftar, kode OTP sudah dikirim ke WhatsApp kamu.",
      });
    }

    const otp = generateOtp();
    const otpHash = await bcrypt.hash(otp, 12);

    await prisma.$transaction(async (tx) => {
      // Hapus OTP login pending yang belum verified untuk user ini —
      // mencegah orphan rows + force pakai OTP terbaru saja.
      await tx.loginOtp.deleteMany({
        where: {
          userId: user.id,
          verifiedAt: null,
        },
      });

      await tx.loginOtp.create({
        data: {
          userId: user.id,
          phone: user.phone!,
          otpHash,
          expiresAt: new Date(Date.now() + OTP_EXPIRES_MS),
        },
      });
    });

    const result = await sendOtpViaWhatsapp({
      phone: user.phone,
      name: user.name,
      otp,
    });

    if (result?.ok === false && !result.skipped) {
      console.error("[member-login-otp] WhatsApp send failed:", result);
      return NextResponse.json(
        { error: "Gagal kirim OTP ke WhatsApp. Coba lagi nanti." },
        { status: 502 },
      );
    }

    return NextResponse.json({
      ok: true,
      message:
        "Kode OTP sudah dikirim ke WhatsApp kamu. Berlaku 5 menit.",
    });
  } catch (error) {
    console.error("[member-login-otp/request] error:", error);
    return NextResponse.json(
      { error: "Permintaan OTP sedang bermasalah. Coba lagi sebentar." },
      { status: 500 },
    );
  }
}
