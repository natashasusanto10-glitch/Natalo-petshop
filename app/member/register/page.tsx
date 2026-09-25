"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { OperatingHoursCard } from "@/components/OperatingHours";
import { PasswordInput } from "@/components/PasswordInput";

function safeRedirect(value: string | null) {
  // Backslash ditolak: parser URL (WHATWG) memperlakukan `\` seperti `/`,
  // jadi tanpa cek ini `/\evil.com` lolos sebagai protocol-relative redirect.
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) return "/";
  if (
    value.startsWith("/api") ||
    value.startsWith("/admin") ||
    value.startsWith("/member/login") ||
    value.startsWith("/member/register")
  ) {
    return "/";
  }
  return value;
}

// Cooldown sebelum "Kirim ulang OTP" boleh ditekan ulang. Fonnte Free plan
// delay 30-60 detik antara queue → delivered, jadi user perlu sabar dulu
// sebelum minta resend. Mencegah double-send + impatient user spam.
const RESEND_COOLDOWN_SEC = 60;

export default function MemberRegisterPage() {
  const [redirectTo, setRedirectTo] = useState("/");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [otp, setOtp] = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [resendCooldown, setResendCooldown] = useState(0);

  useEffect(() => {
    const url = new URL(window.location.href);
    setRedirectTo(safeRedirect(url.searchParams.get("redirect")));
  }, []);

  useEffect(() => {
    if (resendCooldown <= 0) return;
    const id = window.setTimeout(() => setResendCooldown((s) => s - 1), 1000);
    return () => window.clearTimeout(id);
  }, [resendCooldown]);

  // Focus management: setelah error, fokus pindah ke field invalid pertama.
  function focusFirstInvalid(sent: boolean) {
    const id = !name
      ? "reg-name"
      : !email
        ? "reg-email"
        : !phone
          ? "reg-phone"
          : !password
            ? "reg-password"
            : !confirmPassword
              ? "reg-confirm"
              : sent
                ? "reg-otp"
                : "reg-name";
    document.getElementById(id)?.focus();
  }

  const confirmMismatch = !!confirmPassword && confirmPassword !== password;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setNotice("");

    if (password !== confirmPassword) {
      setError("Konfirmasi password tidak sama.");
      focusFirstInvalid(otpSent);
      return;
    }

    if (otpSent && otp.replace(/\D/g, "").length !== 6) {
      setError("Masukkan kode OTP 6 digit.");
      focusFirstInvalid(true);
      return;
    }

    setLoading(true);

    const res = await fetch("/api/auth/member-register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name,
        email,
        phone,
        password,
        confirmPassword,
        otp: otpSent ? otp : "",
      }),
    });

    const data = await res.json();
    setLoading(false);

    if (!res.ok) {
      setError(data.error || "Pendaftaran gagal");
      focusFirstInvalid(otpSent);
      return;
    }

    if (data.otpRequired) {
      setOtpSent(true);
      setResendCooldown(RESEND_COOLDOWN_SEC);
      setNotice(data.message || "Kode OTP sudah dikirim.");
      return;
    }

    const loginParams = new URLSearchParams({ registered: "1" });
    if (redirectTo !== "/") loginParams.set("redirect", redirectTo);
    window.location.replace(`/member/login?${loginParams.toString()}`);
  }

  async function handleResendOtp() {
    if (resendCooldown > 0) return;
    setOtp("");
    setOtpSent(false);
    setNotice("");
    setError("");
    window.setTimeout(() => {
      const form = document.querySelector("form");
      form?.requestSubmit();
    }, 0);
  }

  function unlockEdit() {
    setOtp("");
    setOtpSent(false);
    setNotice("");
    setError("");
  }

  return (
    <div className="auth-aurora min-h-[calc(100svh-64px)] px-4 pb-10 pt-8 md:py-12">
      <div className="mx-auto w-full max-w-sm">
        <section className="auth-rise text-center">
          <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-[20px] bg-white shadow-[0_10px_24px_-8px_rgba(20,62,126,0.22)] ring-1 ring-natalo-700/10">
            <Image
              src="/icons/icon-192x192.png"
              alt="NL Petshop"
              width={44}
              height={44}
              priority
              className="h-11 w-11 rounded-[12px]"
            />
          </div>
          <h1 className="mt-5 text-[26px] font-black leading-tight tracking-tight text-gray-950">
            Mulai Langkahmu!
          </h1>
          <p className="mx-auto mt-2 max-w-xs text-[15px] leading-relaxed text-gray-500">
            Daftar sekarang dan nikmati voucher promo khusus member baru.
          </p>
        </section>

        {notice && (
          <p
            role="status"
            className="auth-rise mt-6 rounded-xl border border-green-200 bg-green-50 px-4 py-3 text-sm font-semibold text-green-700"
          >
            {notice}
          </p>
        )}

        <form
          onSubmit={handleSubmit}
          className="auth-rise auth-rise-d1 mt-7 flex flex-col gap-4"
        >
          <div>
            <label htmlFor="reg-name" className="mb-1.5 block text-[13px] font-bold text-gray-700">
              Nama lengkap
            </label>
            <input
              id="reg-name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              disabled={otpSent}
              autoComplete="name"
              className="auth-input"
              placeholder="Contoh: Andi Setiawan"
            />
          </div>

          <div>
            <label htmlFor="reg-email" className="mb-1.5 block text-[13px] font-bold text-gray-700">
              Email
            </label>
            <input
              id="reg-email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              disabled={otpSent}
              autoComplete="email"
              className="auth-input"
              placeholder="Contoh: nama@email.com"
            />
          </div>

          <div>
            <label htmlFor="reg-phone" className="mb-1.5 block text-[13px] font-bold text-gray-700">
              No. handphone
            </label>
            <input
              id="reg-phone"
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              required
              disabled={otpSent}
              autoComplete="tel"
              className="auth-input"
              placeholder="Contoh: 08123456789"
            />
          </div>

          <div>
            <label
              htmlFor="reg-password"
              className="mb-1.5 block text-[13px] font-bold text-gray-700"
            >
              Password
            </label>
            <PasswordInput
              id="reg-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
              disabled={otpSent}
              autoComplete="new-password"
              className="auth-input"
              placeholder="Buat password"
            />
            <p className="mt-1.5 text-xs text-gray-500">Minimal 8 karakter.</p>
          </div>

          <div>
            <label
              htmlFor="reg-confirm"
              className="mb-1.5 block text-[13px] font-bold text-gray-700"
            >
              Konfirmasi password
            </label>
            <PasswordInput
              id="reg-confirm"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              required
              minLength={8}
              disabled={otpSent}
              autoComplete="new-password"
              className={`auth-input ${confirmMismatch ? "auth-input--invalid" : ""}`}
              placeholder="Ulangi password yang sama"
            />
            {confirmMismatch && (
              <p className="mt-1.5 text-xs font-semibold text-red-500">Password tidak cocok</p>
            )}
          </div>

          {error && (
            <div
              role="alert"
              className="rounded-xl border border-red-100 bg-red-50 px-4 py-3 text-sm font-semibold text-red-600"
            >
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading || confirmMismatch}
            className="auth-cta mt-1 w-full"
          >
            {loading ? (
              <>
                <span className="auth-spinner" aria-hidden />
                Memproses…
              </>
            ) : otpSent ? (
              "Verifikasi & Daftar"
            ) : (
              "Kirim kode OTP"
            )}
          </button>

          <p className="rounded-xl border border-[#e2e9f4] bg-[#f1f5fb] px-3 py-2.5 text-xs leading-relaxed text-slate-600">
            Kode OTP dikirim ke email &amp; WhatsApp kamu. WhatsApp bisa butuh
            30–60 detik — cukup masukkan satu kode yang sama.
          </p>

          {otpSent && (
            <div className="rounded-2xl border border-[#dbe7f7] bg-white p-4 shadow-[0_1px_2px_rgba(15,23,42,0.04)]">
              <label
                htmlFor="reg-otp"
                className="block text-[13px] font-bold text-gray-700"
              >
                Kode OTP
              </label>
              <input
                id="reg-otp"
                type="text"
                inputMode="numeric"
                maxLength={6}
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\D/g, "").slice(0, 6))}
                required
                className="auth-input mt-2 text-center text-lg font-black tracking-[0.35em]"
                placeholder="000000"
              />
              <p className="mt-2 text-xs leading-relaxed text-gray-500">
                Kode berlaku 10 menit. WhatsApp bisa butuh{" "}
                <span className="font-semibold">30–60 detik</span> — kalau cepat, cek inbox email
                kamu dulu. Gunakan salah satu kode yang masuk.
              </p>
              <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs font-bold">
                <button
                  type="button"
                  onClick={handleResendOtp}
                  disabled={resendCooldown > 0}
                  className="text-natalo-700 hover:underline disabled:cursor-not-allowed disabled:text-gray-400 disabled:no-underline"
                >
                  {resendCooldown > 0
                    ? `Kirim ulang OTP (${resendCooldown}s)`
                    : "Kirim ulang OTP"}
                </button>
                <button
                  type="button"
                  onClick={unlockEdit}
                  className="text-gray-500 hover:text-gray-700 hover:underline"
                >
                  Ubah data
                </button>
              </div>
            </div>
          )}
        </form>

        <p className="auth-rise auth-rise-d2 mt-6 text-center text-xs text-gray-500">
          Gratis — kumpulkan poin loyalty &amp; harga khusus member.
        </p>

        <p className="mt-4 text-center text-sm text-gray-500">
          Sudah punya akun?{" "}
          <Link
            href={`/member/login?redirect=${encodeURIComponent(redirectTo)}`}
            className="font-extrabold text-natalo-700 hover:underline"
          >
            Masuk
          </Link>
        </p>
        <OperatingHoursCard className="mt-6" />
      </div>
    </div>
  );
}
