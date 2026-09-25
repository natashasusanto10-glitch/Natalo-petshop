"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { PasswordInput } from "@/components/PasswordInput";
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

function friendlyLoginError(message: string) {
  const lower = message.toLowerCase();
  if (lower.includes("tidak ditemukan")) {
    return "Akun belum ditemukan. Cek lagi email/no. HP kamu atau daftar gratis dulu.";
  }
  if (lower.includes("password")) {
    return "Password belum cocok. Coba cek kembali atau gunakan fitur lupa password.";
  }
  if (lower.includes("wajib")) {
    return "Isi email/no. HP dan password terlebih dahulu.";
  }
  return message || "Login belum berhasil. Coba beberapa saat lagi.";
}

export default function MemberLoginPage() {
  const router = useRouter();
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [redirectTo, setRedirectTo] = useState("/");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const url = new URL(window.location.href);
    setRedirectTo(safeRedirect(url.searchParams.get("redirect")));
    if (url.searchParams.get("registered") === "1") {
      setNotice("Pendaftaran berhasil! Silakan masuk dengan email/no. HP & password kamu.");
      url.searchParams.delete("registered");
      window.history.replaceState({}, "", url.toString());
    }
  }, []);

  // Focus management: setelah error submit, fokus pindah ke field invalid
  // pertama (identifier kosong → identifier; selain itu → password) supaya
  // keyboard & screen reader user langsung berada di titik yang perlu
  // diperbaiki tanpa Tab manual.
  function focusFirstInvalid() {
    document.getElementById(identifier ? "auth-password" : "auth-identifier")?.focus();
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setNotice("");
    setLoading(true);

    const res = await fetch("/api/auth/member-login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({ identifier, password }),
    });

    const data = await res.json();
    setLoading(false);

    if (!res.ok) {
      setError(friendlyLoginError(data.error || "Login gagal"));
      focusFirstInvalid();
      return;
    }

    await mergeFromServer().catch(() => {});
    dispatchAuthUpdated();

    router.replace(redirectTo);
    router.refresh();
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
            Selamat Datang Kembali!
          </h1>
          <p className="mx-auto mt-2 max-w-xs text-[15px] leading-relaxed text-gray-500">
            Masuk untuk melanjutkan belanja kebutuhan hewan kesayanganmu.
          </p>
        </section>

        {notice && (
          <div
            role="status"
            className="auth-rise mt-6 flex items-start gap-3 rounded-2xl border border-green-200 bg-green-50 px-4 py-3 text-sm font-semibold text-green-800"
          >
            <span
              aria-hidden
              className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-green-500 text-xs text-white"
            >
              ✓
            </span>
            <p className="leading-snug">{notice}</p>
          </div>
        )}

        <form
          onSubmit={handleSubmit}
          className="auth-rise auth-rise-d1 mt-7 flex flex-col gap-4"
        >
          <div>
            <label
              htmlFor="auth-identifier"
              className="mb-1.5 block text-[13px] font-bold text-gray-700"
            >
              Email atau No. Handphone
            </label>
            <input
              id="auth-identifier"
              type="text"
              value={identifier}
              onChange={(e) => setIdentifier(e.target.value)}
              required
              autoComplete="username"
              inputMode="email"
              className="auth-input"
              placeholder="Contoh: 08123456789 / nama@email.com"
            />
          </div>

          <div>
            <div className="flex items-baseline justify-between gap-3">
              <label
                htmlFor="auth-password"
                className="mb-1.5 block text-[13px] font-bold text-gray-700"
              >
                Password
              </label>
              <Link
                href="/member/forgot-password"
                className="px-0.5 py-2 text-xs font-bold text-natalo-700 transition hover:text-natalo-800 hover:underline"
              >
                Lupa password?
              </Link>
            </div>
            <PasswordInput
              id="auth-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              autoComplete="current-password"
              className="auth-input"
              placeholder="Masukkan password"
              disabled={loading}
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
              "Masuk"
            )}
          </button>

          <div
            className="flex items-center gap-3 text-xs font-semibold text-gray-400"
            role="separator"
          >
            <span className="h-px flex-1 bg-gray-200" />
            atau masuk lebih cepat
            <span className="h-px flex-1 bg-gray-200" />
          </div>

          <Link
            href={`/member/login-otp?redirect=${encodeURIComponent(redirectTo)}`}
            className="auth-cta-secondary w-full"
          >
            <svg
              aria-hidden
              viewBox="0 0 24 24"
              fill="currentColor"
              width={18}
              height={18}
            >
              <path d="M20.52 3.48A12 12 0 0 0 3.5 20.36L2 22l1.69-1.55A12 12 0 1 0 20.52 3.48Zm-8.4 18a10 10 0 0 1-5.1-1.4l-.36-.21-3.06.86.82-3-.24-.38a10 10 0 1 1 7.94 4.13Zm5.5-7.5c-.3-.15-1.78-.88-2-1s-.5-.15-.7.15-.82 1-1 1.2-.36.22-.66.07a8.2 8.2 0 0 1-2.4-1.48 9.05 9.05 0 0 1-1.66-2.07c-.17-.3 0-.46.13-.61s.3-.36.45-.54a2.1 2.1 0 0 0 .3-.5.55.55 0 0 0 0-.53c-.07-.15-.7-1.67-.95-2.28s-.5-.52-.7-.53h-.6a1.16 1.16 0 0 0-.83.39 3.5 3.5 0 0 0-1.1 2.6 6.07 6.07 0 0 0 1.27 3.23 13.92 13.92 0 0 0 5.34 4.7c.74.32 1.32.5 1.78.65a4.3 4.3 0 0 0 2 .12 3.24 3.24 0 0 0 2.13-1.5 2.65 2.65 0 0 0 .19-1.5c-.07-.13-.27-.2-.57-.35Z" />
            </svg>
            Masuk dengan OTP WhatsApp
          </Link>
        </form>

        <p className="auth-rise auth-rise-d2 mt-6 text-center text-sm text-gray-500">
          Belum punya akun?{" "}
          <Link
            href={`/member/register?redirect=${encodeURIComponent(redirectTo)}`}
            className="font-extrabold text-natalo-700 hover:underline"
          >
            Daftar gratis
          </Link>
        </p>
      </div>
    </div>
  );
}
