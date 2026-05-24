import { NextRequest, NextResponse } from "next/server";
import { randomInt } from "crypto";
import { prisma } from "@/lib/prisma";
import { normalizeIndonesianPhone } from "@/lib/phone";
import { sendRegistrationOtpEmail } from "@/lib/email";
import { sendCustomMessage } from "@/lib/whatsapp";
import {
  checkLimit,
  getClientIp as getClientIpFromHeaders,
  getOtpLimiter,
} from "@/lib/rate-limit";
import {
  validateUsernameFormat,
  checkUsernameAvailability,
} from "@/lib/username";
import bcrypt from "bcryptjs";

const OTP_EXPIRES_MS = 10 * 60_000;
const MAX_VERIFY_ATTEMPTS = 5;

function generateOtp() {
  return String(randomInt(100000, 1000000));
}

function isValidEmail(email: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function parsePayload(body: Record<string, unknown>) {
  const name = String(body.name || "").trim();
  // Username dipilih user di register form, mandatory untuk user baru.
  // Di-lowercase + trim disini supaya konsisten dengan format validation
  // di lib/username.ts. Empty string kalau client lama (pre-Fase 1.4)
  // yang belum kirim field ini — validasi handle di validatePayload.
  const username = String(body.username || "").trim().toLowerCase();
  const email = String(body.email || "").trim().toLowerCase();
  const phone = normalizeIndonesianPhone(String(body.phone || ""));
  const password = String(body.password || "");
  const confirmPassword = String(body.confirmPassword || "");
  const otp = String(body.otp || "").replace(/\D/g, "");

  return { name, username, email, phone, password, confirmPassword, otp };
}

function validatePayload(payload: ReturnType<typeof parsePayload>) {
  if (!payload.name || !payload.email || !payload.phone || !payload.password || !payload.confirmPassword) {
    return "Semua field wajib diisi";
  }

  if (!payload.username) {
    return "Username wajib diisi";
  }

  const formatError = validateUsernameFormat(payload.username);
  if (formatError) return formatError.message;

  if (!isValidEmail(payload.email)) {
    return "Format email tidak valid";
  }

  if (payload.phone.length < 8 || !payload.phone.startsWith("0")) {
    return "Nomor handphone tidak valid";
  }

  if (payload.password.length < 8) {
    return "Password minimal 8 karakter";
  }

  if (payload.password !== payload.confirmPassword) {
    return "Konfirmasi password tidak sama";
  }

  return null;
}

async function ensureNotRegistered(email: string, phone: string) {
  const existing = await prisma.user.findFirst({
    where: {
      OR: [{ email }, { phone }],
    },
    select: { id: true },
  });

  return !existing;
}

async function sendWhatsappOtp({ phone, name, otp }: { phone: string; name: string; otp: string }) {
  const message = [
    `Kode OTP pendaftaran member Natalo Petshop: ${otp}`,
    "",
    "Kode berlaku 10 menit. Jangan bagikan kode ini ke siapa pun.",
  ].join("\n");

  if (!process.env.FONNTE_TOKEN?.trim()) {
    console.log("\n" + "=".repeat(60));
    console.log("[DEV MODE] OTP WhatsApp daftar member");
    console.log("=".repeat(60));
    console.log(`To     : ${phone}`);
    console.log(`Halo   : ${name}`);
    console.log(`OTP    : ${otp}`);
    console.log(`Expires: 10 menit`);
    console.log("=".repeat(60));
    console.log("Set FONNTE_TOKEN di .env untuk kirim WhatsApp beneran.\n");
    return { ok: true };
  }

  return sendCustomMessage(phone, message);
}

async function sendOtpToBothChannels({
  email,
  phone,
  name,
  otp,
}: {
  email: string;
  phone: string;
  name: string;
  otp: string;
}) {
  const [emailResult, waResult] = await Promise.allSettled([
    sendRegistrationOtpEmail({ to: email, userName: name, otp }),
    sendWhatsappOtp({ phone, name, otp }),
  ]);

  const emailOk = emailResult.status === "fulfilled" && emailResult.value?.ok !== false;
  const waOk = waResult.status === "fulfilled" && waResult.value?.ok !== false;

  if (!emailOk && emailResult.status === "rejected") {
    console.error("[register-otp] email send failed:", emailResult.reason);
  }
  if (!waOk && waResult.status === "rejected") {
    console.error("[register-otp] whatsapp send failed:", waResult.reason);
  }

  return { emailOk, waOk };
}

export async function POST(request: NextRequest) {
  const body = await request.json();
  const payload = parsePayload(body);
  const validationError = validatePayload(payload);

  if (validationError) {
    return NextResponse.json({ error: validationError }, { status: 400 });
  }

  const stillAvailable = await ensureNotRegistered(payload.email, payload.phone);
  if (!stillAvailable) {
    return NextResponse.json({ error: "Email atau no. handphone sudah terdaftar" }, { status: 409 });
  }

  // Username uniqueness check — server-side, baik di step-1 (send OTP)
  // maupun step-2 (verify OTP). Stop early kalau username taken/reserved
  // supaya user tidak waste OTP step dengan handle yang konflik. Skip
  // `excludeUserId` karena user belum ada (sign-up flow).
  const usernameStatus = await checkUsernameAvailability(payload.username);
  if (!usernameStatus.available) {
    return NextResponse.json(
      {
        error: usernameStatus.reason === "TAKEN"
          ? "Username sudah dipakai. Coba yang lain."
          : "Username ini baru saja dilepas. Pilih yang lain (reservasi 30 hari).",
        field: "username",
      },
      { status: 409 },
    );
  }

  if (payload.otp) {
    const pending = await prisma.registrationOtp.findFirst({
      where: {
        email: payload.email,
        phone: payload.phone,
        verifiedAt: null,
      },
      orderBy: { createdAt: "desc" },
    });

    if (!pending) {
      return NextResponse.json({ error: "Kode OTP belum diminta atau sudah tidak berlaku." }, { status: 400 });
    }

    if (pending.expiresAt < new Date()) {
      return NextResponse.json({ error: "Kode OTP sudah kedaluwarsa. Minta kode baru." }, { status: 400 });
    }

    if (pending.attempts >= MAX_VERIFY_ATTEMPTS) {
      return NextResponse.json({ error: "Terlalu banyak percobaan OTP. Minta kode baru." }, { status: 429 });
    }

    const validOtp = await bcrypt.compare(payload.otp, pending.otpHash);
    if (!validOtp) {
      await prisma.registrationOtp.update({
        where: { id: pending.id },
        data: { attempts: { increment: 1 } },
      });
      return NextResponse.json({ error: "Kode OTP salah." }, { status: 400 });
    }

    // Transaction return user yang baru dibuat — supaya response bisa
    // include user data. Flutter `authService.register()` parse field
    // `user` di response untuk detect Step 2 sukses. Tanpa field user,
    // Flutter salah anggap masih di Step 1 → snackbar "Kode OTP dikirim"
    // muncul lagi → user kira gagal → klik Daftar lagi → 409 "sudah
    // terdaftar" → confused.
    const createdUser = await prisma.$transaction(async (tx) => {
      await tx.registrationOtp.update({
        where: { id: pending.id },
        data: { verifiedAt: new Date() },
      });

      // Defensive: pending.username bisa null (row legacy pre-Fase 1.4).
      // Fallback ke payload.username yang current (sudah re-validated di
      // atas). Step-2 verifyOtp dipanggil setelah validation pass, jadi
      // payload.username konsisten dengan input user.
      const finalUsername = pending.username ?? payload.username;
      const now = new Date();
      return tx.user.create({
        data: {
          name: pending.name,
          username: finalUsername,
          usernameUpdatedAt: now,
          email: pending.email,
          phone: pending.phone,
          passwordHash: pending.passwordHash,
          role: "CUSTOMER",
        },
        // Select explicit — JANGAN return passwordHash / sensitive
        // field ke client. Match shape MemberProfile.fromApiJson di
        // Flutter side (perlu id, name, username, email, phone, role).
        select: {
          id: true,
          name: true,
          username: true,
          email: true,
          phone: true,
          role: true,
          profilePhotoUrl: true,
          bio: true,
          createdAt: true,
        },
      });
    });

    return NextResponse.json({
      ok: true,
      registered: true,
      user: createdUser,
    });
  }

  const ip = getClientIpFromHeaders(request.headers);
  const rateKey = `register-otp:${ip}:${payload.email}:${payload.phone}`;
  const gate = await checkLimit(getOtpLimiter(), rateKey);
  if (!gate.ok) {
    return NextResponse.json(
      { error: "Terlalu banyak permintaan OTP. Coba lagi nanti." },
      { status: 429, headers: { "Retry-After": String(gate.retryAfter) } },
    );
  }

  const otp = generateOtp();
  const [otpHash, passwordHash] = await Promise.all([
    bcrypt.hash(otp, 12),
    bcrypt.hash(payload.password, 12),
  ]);

  await prisma.$transaction(async (tx) => {
    await tx.registrationOtp.deleteMany({
      where: {
        OR: [{ email: payload.email }, { phone: payload.phone }],
        verifiedAt: null,
      },
    });

    await tx.registrationOtp.create({
      data: {
        name: payload.name,
        username: payload.username,
        email: payload.email,
        phone: payload.phone,
        passwordHash,
        channel: "BOTH",
        otpHash,
        expiresAt: new Date(Date.now() + OTP_EXPIRES_MS),
      },
    });
  });

  const { emailOk, waOk } = await sendOtpToBothChannels({
    email: payload.email,
    phone: payload.phone,
    name: payload.name,
    otp,
  });

  if (!emailOk && !waOk) {
    return NextResponse.json(
      { error: "Gagal mengirim OTP ke email maupun WhatsApp. Coba lagi atau hubungi admin." },
      { status: 502 }
    );
  }

  // Pesan jujur tentang delay Fonnte Free plan (WA bisa pending 30-60s di
  // queue). Email biasanya jauh lebih cepat, jadi arahkan user cek email dulu.
  let message: string;
  if (emailOk && waOk) {
    message =
      "OTP dikirim. WhatsApp bisa butuh 30–60 detik — sementara cek email kamu dulu.";
  } else if (emailOk) {
    message = "Kode OTP dikirim ke email (pengiriman WhatsApp gagal). Cek inbox email kamu.";
  } else {
    message =
      "Kode OTP dikirim ke WhatsApp (pengiriman email gagal). Tunggu 30–60 detik atau cek folder spam.";
  }

  return NextResponse.json({
    ok: true,
    otpRequired: true,
    emailOk,
    waOk,
    message,
  });
}
