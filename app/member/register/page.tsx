"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { OperatingHoursCard } from "@/components/OperatingHours";
import { PasswordInput } from "@/components/PasswordInput";

function safeRedirect(value: string | null) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return "/";
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

  useEffect(() => {
    const url = new URL(window.location.href);
    setRedirectTo(safeRedirect(url.searchParams.get("redirect")));
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setNotice("");

    if (password !== confirmPassword) {
      setError("Konfirmasi password tidak sama.");
      return;
    }

    if (otpSent && otp.replace(/\D/g, "").length !== 6) {
      setError("Masukkan kode OTP 6 digit.");
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
      return;
    }

    if (data.otpRequired) {
      setOtpSent(true);
      setNotice(data.message || "Kode OTP sudah dikirim.");
      return;
    }

    const loginParams = new URLSearchParams({ registered: "1" });
    if (redirectTo !== "/") loginParams.set("redirect", redirectTo);
    window.location.replace(`/member/login?${loginParams.toString()}`);
  }

  async function handleResendOtp() {
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
    <div className="flex min-h-screen items-start justify-center bg-gray-50 px-4 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <div className="mx-auto flex h-20 w-20 items-center justify-center rounded-[26px] bg-white p-2 shadow-sm ring-1 ring-blue-100">
            <Image
              src="/icons/icon-192x192.png"
              alt="NL Petshop"
              width={64}
              height={64}
              priority
              className="h-16 w-16 rounded-2xl"
            />
          </div>
          <h1 className="mt-4 text-2xl font-black tracking-tight text-gray-950">
            Daftar Member Natalo
          </h1>
          <p className="mt-1 text-sm text-gray-500">Gratis! Dapatkan harga khusus dan benefit member.</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4 rounded-3xl bg-white p-8 shadow-sm">
          <div>
            <label className="block text-sm font-medium text-gray-700">Nama lengkap</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              disabled={otpSent}
              className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
              placeholder="Contoh: Andi Setiawan"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Email</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              disabled={otpSent}
              className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
              placeholder="Contoh: nama@email.com"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">No. handphone</label>
            <input
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              required
              disabled={otpSent}
              className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
              placeholder="Contoh: 08123456789"
            />
          </div>

          <div className="rounded-xl border border-blue-100 bg-blue-50/60 px-4 py-3 text-xs text-blue-800">
            <p className="font-semibold">Kode OTP akan dikirim ke email <span className="underline">dan</span> WhatsApp kamu.</p>
            <p className="mt-1 text-blue-700/80">Pastikan keduanya aktif — kamu cukup masukkan satu kode yang sama.</p>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Password</label>
            <PasswordInput
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
              disabled={otpSent}
              className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
              placeholder="Masukkan password (min. 8 karakter)"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Konfirmasi password</label>
            <PasswordInput
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              required
              minLength={8}
              disabled={otpSent}
              className={`mt-1 block w-full rounded-xl border px-4 py-3 text-sm outline-none transition focus:ring-2 ${
                confirmPassword && confirmPassword !== password
                  ? "border-red-300 focus:border-red-400 focus:ring-red-100"
                  : "border-gray-200 focus:border-blue-400 focus:ring-blue-100"
              }`}
              placeholder="Ulangi password yang sama"
            />
            {confirmPassword && confirmPassword !== password && (
              <p className="mt-1 text-xs text-red-500">Password tidak cocok</p>
            )}
          </div>

          {otpSent && (
            <div className="rounded-2xl border border-blue-100 bg-blue-50 p-4">
              <label className="block text-sm font-bold text-gray-900">Kode OTP</label>
              <input
                type="text"
                inputMode="numeric"
                maxLength={6}
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\D/g, "").slice(0, 6))}
                required
                className="mt-2 block w-full rounded-xl border border-blue-200 bg-white px-4 py-3 text-center text-lg font-black tracking-[0.35em] outline-none transition focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
                placeholder="000000"
              />
              <p className="mt-2 text-xs text-gray-600">
                Kode berlaku 10 menit. Cek inbox email atau WhatsApp kamu — gunakan salah satunya.
              </p>
              <div className="mt-3 flex flex-wrap gap-3 text-xs font-bold">
                <button type="button" onClick={handleResendOtp} className="text-blue-700 hover:underline">
                  Kirim ulang OTP
                </button>
                <button type="button" onClick={unlockEdit} className="text-gray-600 hover:underline">
                  Ubah data
                </button>
              </div>
            </div>
          )}

          {notice && (
            <p className="rounded-xl bg-green-50 px-4 py-3 text-sm text-green-700">{notice}</p>
          )}

          {error && (
            <p className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-600">{error}</p>
          )}

          <button
            type="submit"
            disabled={loading || (!!confirmPassword && confirmPassword !== password)}
            className="w-full rounded-full bg-blue-500 py-3 text-sm font-bold text-white transition hover:bg-blue-600 disabled:opacity-50"
          >
            {loading ? "Memproses..." : otpSent ? "Verifikasi & Daftar" : "Kirim OTP"}
          </button>

          <div className="rounded-xl border border-gray-200 bg-gray-50 px-5 py-4 text-sm text-gray-700">
            <p className="text-center font-semibold text-gray-900">
              Manfaat jadi Member di Natalopetshop.com
            </p>
            <ul className="mt-3 list-disc space-y-1 pl-5">
              <li>Kumpulkan Loyalty poin dari setiap transaksi anda.</li>
              <li>Belanja di natalopetshop.com lebih murah, cepat, hemat dan mudah.</li>
            </ul>
          </div>
        </form>

        <p className="mt-6 text-center text-sm text-gray-500">
          Sudah punya akun?{" "}
          <Link
            href={`/member/login?redirect=${encodeURIComponent(redirectTo)}`}
            className="font-semibold text-blue-600 hover:underline"
          >
            Masuk
          </Link>
        </p>
        <OperatingHoursCard className="mt-6" />
      </div>
    </div>
  );
}
