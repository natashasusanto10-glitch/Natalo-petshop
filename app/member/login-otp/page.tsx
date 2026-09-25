"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { dispatchAuthUpdated, mergeFromServer } from "@/lib/cart";

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

// OTP login berlaku 5 menit di server (lebih pendek dari register) — user
// yang request login biasanya online, jadi cooldown resend singkat saja.
const RESEND_COOLDOWN_SEC = 30;

export default function MemberLoginOtpPage() {
  const router = useRouter();
  const [redirectTo, setRedirectTo] = useState("/");
  const [phone, setPhone] = useState("");
  const [otp, setOtp] = useState("");
  const [step, setStep] = useState<"phone" | "otp">("phone");
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

  function focusFirstInvalid(isPhoneStep: boolean) {
    document.getElementById(isPhoneStep ? "otp-phone" : "login-otp-code")?.focus();
  }

  async function handleRequestOtp() {
    setError("");
    setNotice("");
    setLoading(true);

    const res = await fetch("/api/auth/member-login-otp/request", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ phone }),
    });

    const data = await res.json();
    setLoading(false);

    if (!res.ok) {
      setError(data.error || "Permintaan OTP belum berhasil.");
      focusFirstInvalid(true);
      return;
    }

    setStep("otp");
    setResendCooldown(RESEND_COOLDOWN_SEC);
    setNotice(data.message || "Kode OTP sudah dikirim ke WhatsApp kamu.");
    // Fokus langsung ke field OTP — user tidak perlu tap ulang setelah
    // pindah aplikasi WhatsApp.
    window.setTimeout(() => focusFirstInvalid(false), 0);
  }

  async function handleVerifyOtp(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setNotice("");

    if (otp.replace(/\D/g, "").length !== 6) {
      setError("Masukkan kode OTP 6 digit.");
      focusFirstInvalid(false);
      return;
    }

    setLoading(true);

    const res = await fetch("/api/auth/member-login-otp/verify", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({ phone, otp }),
    });

    const data = await res.json();
    setLoading(false);

    if (!res.ok) {
      setError(data.error || "Login OTP belum berhasil.");
      focusFirstInvalid(false);
      return;
    }

    await mergeFromServer().catch(() => {});
    dispatchAuthUpdated();

    router.replace(redirectTo);
    router.refresh();
  }

  function handleResend() {
    if (resendCooldown > 0 || loading) return;
    setOtp("");
    setNotice("");
    setError("");
    void handleRequestOtp();
  }

  function changePhone() {
    setStep("phone");
    setOtp("");
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
            Masuk dengan OTP
          </h1>
          <p className="mx-auto mt-2 max-w-xs text-[15px] leading-relaxed text-gray-500">
            Kami kirim kode 6 digit ke WhatsApp kamu.
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

        {step === "phone" ? (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              void handleRequestOtp();
            }}
            className="auth-rise auth-rise-d1 mt-7 flex flex-col gap-4"
          >
            <div>
              <label
                htmlFor="otp-phone"
                className="mb-1.5 block text-[13px] font-bold text-gray-700"
              >
                No. WhatsApp terdaftar
              </label>
              <input
                id="otp-phone"
                type="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                required
                autoComplete="tel"
                className="auth-input"
                placeholder="Contoh: 08123456789"
              />
            </div>

            {error && (
              <div
                role="alert"
                className="rounded-xl border border-red-100 bg-red-50 px-4 py-3 text-sm font-semibold text-red-600"
              >
                {error}
              </div>
            )}

            <button type="submit" disabled={loading} className="auth-cta mt-1 w-full">
              {loading ? (
                <>
                  <span className="auth-spinner" aria-hidden />
                  Memproses…
                </>
              ) : (
                "Kirim kode OTP"
              )}
            </button>

            <p className="rounded-xl border border-[#e2e9f4] bg-[#f1f5fb] px-3 py-2.5 text-xs leading-relaxed text-slate-600">
              Kode berlaku 5 menit dan dikirim via WhatsApp. Pastikan nomor
              sama dengan yang kamu daftarkan.
            </p>
          </form>
        ) : (
          <form
            onSubmit={handleVerifyOtp}
            className="auth-rise auth-rise-d1 mt-7 flex flex-col gap-4"
          >
            <div>
              <label
                htmlFor="login-otp-code"
                className="mb-1.5 block text-[13px] font-bold text-gray-700"
              >
                Kode OTP untuk {phone}
              </label>
              <input
                id="login-otp-code"
                type="text"
                inputMode="numeric"
                maxLength={6}
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\D/g, "").slice(0, 6))}
                required
                className="auth-input text-center text-lg font-black tracking-[0.35em]"
                placeholder="000000"
              />
            </div>

            {error && (
              <div
                role="alert"
                className="rounded-xl border border-red-100 bg-red-50 px-4 py-3 text-sm font-semibold text-red-600"
              >
                {error}
              </div>
            )}

            <button type="submit" disabled={loading} className="auth-cta mt-1 w-full">
              {loading ? (
                <>
                  <span className="auth-spinner" aria-hidden />
                  Memproses…
                </>
              ) : (
                "Verifikasi & Masuk"
              )}
            </button>

            <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs font-bold">
              <button
                type="button"
                onClick={handleResend}
                disabled={resendCooldown > 0 || loading}
                className="text-natalo-700 hover:underline disabled:cursor-not-allowed disabled:text-gray-400 disabled:no-underline"
              >
                {resendCooldown > 0
                  ? `Kirim ulang OTP (${resendCooldown}s)`
                  : "Kirim ulang OTP"}
              </button>
              <button
                type="button"
                onClick={changePhone}
                className="text-gray-500 hover:text-gray-700 hover:underline"
              >
                Ubah nomor
              </button>
            </div>
          </form>
        )}

        <div
          className="auth-rise auth-rise-d2 mt-7 flex items-center gap-3 text-xs font-semibold text-gray-400"
          role="separator"
        >
          <span className="h-px flex-1 bg-gray-200" />
          atau
          <span className="h-px flex-1 bg-gray-200" />
        </div>

        <Link
          href={`/member/login?redirect=${encodeURIComponent(redirectTo)}`}
          className="auth-cta-secondary mt-4 w-full"
        >
          Masuk dengan password
        </Link>
      </div>
    </div>
  );
}
