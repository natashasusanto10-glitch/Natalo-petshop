"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { PasswordInput } from "@/components/PasswordInput";
import { dispatchAuthUpdated, mergeFromServer } from "@/lib/cart";

function safeRedirect(value: string | null) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return "/member";
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
  const [redirectTo, setRedirectTo] = useState("/member");
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
      return;
    }

    await mergeFromServer().catch(() => {});
    dispatchAuthUpdated();

    router.push(redirectTo);
    router.refresh();
  }

  return (
    <div className="min-h-[calc(100svh-72px)] bg-gradient-to-b from-blue-50 via-[#FAFAFA] to-white px-4 pb-8 pt-6 md:py-12">
      <div className="mx-auto w-full max-w-md">
        <section className="text-center">
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
            Masuk Member Natalo
          </h1>
          <p className="mx-auto mt-2 max-w-xs text-sm font-medium leading-relaxed text-gray-500">
            Belanja kebutuhan hewan jadi lebih mudah, cepat, dan hemat.
          </p>
        </section>

        {notice && (
          <div className="mt-6 flex items-start gap-3 rounded-2xl border border-green-200 bg-green-50 px-4 py-3 text-sm font-semibold text-green-800">
            <span aria-hidden className="mt-0.5 flex h-5 w-5 items-center justify-center rounded-full bg-green-500 text-xs text-white">
              ✓
            </span>
            <p className="leading-snug">{notice}</p>
          </div>
        )}

        <form
          onSubmit={handleSubmit}
          className="mt-6 space-y-4 rounded-[28px] border border-blue-50 bg-white p-5 shadow-[0_12px_35px_rgba(30,95,191,0.10)] sm:p-7"
        >
          <div className="rounded-2xl bg-blue-50/70 px-4 py-3">
            <p className="text-sm font-black text-blue-900">Akun member Natalo</p>
            <p className="mt-0.5 text-xs font-medium text-blue-700">
              Masuk untuk lanjut checkout, cek pesanan, dan pakai benefit member.
            </p>
          </div>

          <div>
            <label className="block text-sm font-bold text-gray-700">Email / No. HP</label>
            <input
              type="text"
              value={identifier}
              onChange={(e) => setIdentifier(e.target.value)}
              required
              autoComplete="username"
              inputMode="email"
              className="mt-1.5 block w-full rounded-2xl border border-gray-200 bg-white px-4 py-3 text-sm text-gray-900 outline-none transition placeholder:text-gray-400 focus:border-blue-500 focus:ring-4 focus:ring-blue-100"
              placeholder="Masukan Email / No Hp"
            />
          </div>

          <div>
            <div className="flex items-center justify-between gap-3">
              <label className="block text-sm font-bold text-gray-700">Password</label>
              <Link
                href="/member/forgot-password"
                className="text-xs font-bold text-blue-600 transition hover:text-blue-700 hover:underline"
              >
                Lupa password?
              </Link>
            </div>
            <PasswordInput
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              autoComplete="current-password"
              className="block w-full rounded-2xl border border-gray-200 bg-white px-4 py-3 text-sm text-gray-900 outline-none transition placeholder:text-gray-400 focus:border-blue-500 focus:ring-4 focus:ring-blue-100"
              placeholder="Masukkan password"
              disabled={loading}
            />
          </div>

          {error && (
            <div className="rounded-2xl border border-red-100 bg-red-50 px-4 py-3 text-sm font-semibold text-red-600">
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="flex h-12 w-full items-center justify-center rounded-full bg-blue-500 text-sm font-black text-white shadow-[0_8px_18px_rgba(30,95,191,0.25)] transition hover:bg-blue-600 active:opacity-90 disabled:cursor-not-allowed disabled:bg-gray-300 disabled:shadow-none"
          >
            {loading ? "Memproses..." : "Masuk"}
          </button>

          <div className="border-t border-gray-100 pt-4 text-center">
            <p className="text-sm text-gray-500">
              Belum punya akun?{" "}
              <Link href="/member/register" className="font-black text-blue-600 hover:underline">
                Daftar gratis
              </Link>
            </p>
            <p className="mt-1 text-xs font-medium text-gray-400">
              Daftar gratis dan mulai kumpulkan benefit member Natalo.
            </p>
          </div>
        </form>
      </div>
    </div>
  );
}
