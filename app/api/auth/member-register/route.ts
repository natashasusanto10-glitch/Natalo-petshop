import { NextRequest, NextResponse } from "next/server";
import { randomInt } from "crypto";
import { prisma } from "@/lib/prisma";
import { normalizeIndonesianPhone } from "@/lib/phone";
import { sendRegistrationOtpEmail } from "@/lib/email";
import { sendCustomMessage } from "@/lib/whatsapp";
import bcrypt from "bcryptjs";

type Bucket = { count: number; resetAt: number };

const buckets = new Map<string, Bucket>();
const WINDOW_MS = 10 * 60_000;
const MAX_REQUESTS = 5;
const OTP_EXPIRES_MS = 10 * 60_000;
const MAX_VERIFY_ATTEMPTS = 5;

function getClientIp(request: NextRequest) {
  return (
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    request.headers.get("x-real-ip") ??
    "unknown"
  );
}

function checkRateLimit(key: string) {
  const now = Date.now();
  const bucket = buckets.get(key);

  if (!bucket || bucket.resetAt < now) {
    buckets.set(key, { count: 1, resetAt: now + WINDOW_MS });
    return { ok: true };
  }

  if (bucket.count >= MAX_REQUESTS) {
    return { ok: false, retryAfter: Math.ceil((bucket.resetAt - now) / 1000) };
  }

  bucket.count += 1;
  return { ok: true };
}

function generateOtp() {
  return String(randomInt(100000, 1000000));
}

function isValidEmail(email: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function parsePayload(body: Record<string, unknown>) {
  const name = String(body.name || "").trim();
  const email = String(body.email || "").trim().toLowerCase();
  const phone = normalizeIndonesianPhone(String(body.phone || ""));
  const password = String(body.password || "");
  const confirmPassword = String(body.confirmPassword || "");
  const otp = String(body.otp || "").replace(/\D/g, "");

  return { name, email, phone, password, confirmPassword, otp };
}

function validatePayload(payload: ReturnType<typeof parsePayload>) {
  if (!payload.name || !payload.email || !payload.phone || !payload.password || !payload.confirmPassword) {
    return "Semua field wajib diisi";
  }

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

    await prisma.$transaction(async (tx) => {
      await tx.registrationOtp.update({
        where: { id: pending.id },
        data: { verifiedAt: new Date() },
      });

      await tx.user.create({
        data: {
          name: pending.name,
          email: pending.email,
          phone: pending.phone,
          passwordHash: pending.passwordHash,
          role: "CUSTOMER",
        },
      });
    });

    return NextResponse.json({ ok: true, registered: true });
  }

  const rateKey = `member-register-otp:${getClientIp(request)}:${payload.email}:${payload.phone}`;
  const gate = checkRateLimit(rateKey);
  if (!gate.ok) {
    return NextResponse.json(
      { error: "Terlalu banyak permintaan OTP. Coba lagi nanti." },
      { status: 429, headers: { "Retry-After": String(gate.retryAfter) } }
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
