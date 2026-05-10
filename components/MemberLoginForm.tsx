"use client";

import { useEffect, useState } from "react";
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

export function MemberLoginForm({ registered }: { registered: boolean }) {
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [redirectTo, setRedirectTo] = useState("/");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const url = new URL(window.location.href);
    setRedirectTo(safeRedirect(url.searchParams.get("redirect")));
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
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
      setError(data.error || "Login gagal");
      return;
    }

    window.location.replace(redirectTo);
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-stone-50 px-4 py-10">
      <div className="w-full max-w-md">
        <div className="rounded-2xl border border-zinc-200 bg-white p-10">
          <div className="mb-6 flex items-center gap-2">
            <span className="text-2xl" aria-hidden="true">
              🐾
            </span>
            <span className="text-base font-semibold text-zinc-900">
              Natalo Petshop
            </span>
          </div>

          <h1 className="text-2xl font-bold tracking-tight text-zinc-950">
            Masuk ke akunmu
          </h1>
          <p className="mt-1 text-sm text-zinc-500">
            Gunakan email atau nomor HP yang terdaftar.
          </p>

          {registered && (
            <p className="mt-4 rounded-lg bg-green-50 px-3.5 py-2.5 text-sm font-semibold text-green-700">
              Pendaftaran berhasil. Silakan masuk dengan akun barumu.
            </p>
          )}

          <form onSubmit={handleSubmit} className="mt-7 space-y-4">
            <div className="flex flex-col gap-1.5">
              <label className="text-sm font-medium text-zinc-700">
                Email / No. HP
              </label>
              <input
                type="text"
                value={identifier}
                onChange={(e) => setIdentifier(e.target.value)}
                required
                autoComplete="username"
                className="rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm text-zinc-900 outline-none transition focus:border-natalo-600"
                placeholder="nama@email.com atau 08123456789"
              />
            </div>

            <div className="flex flex-col gap-1.5">
              <div className="flex items-center justify-between">
                <label className="text-sm font-medium text-zinc-700">
                  Password
                </label>
                <Link
                  href="/member/forgot-password"
                  className="text-xs font-semibold text-natalo-700 hover:underline"
                >
                  Lupa password?
                </Link>
              </div>
              <PasswordInput
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                autoComplete="current-password"
                className="rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm text-zinc-900 outline-none transition focus:border-natalo-600"
                placeholder="Masukkan password"
              />
            </div>

            {error && (
              <div className="rounded-lg bg-red-50 px-3.5 py-2.5 text-sm text-red-700">
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={loading || !identifier || !password}
              className="mt-1 w-full rounded-lg bg-natalo-600 py-3 text-sm font-semibold text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {loading ? "Memeriksa..." : "Masuk"}
            </button>
          </form>

          <p className="mt-6 text-center text-sm text-zinc-500">
            Belum punya akun?{" "}
            <Link
              href={`/member/register?redirect=${encodeURIComponent(redirectTo)}`}
              className="font-semibold text-natalo-700 hover:underline"
            >
              Daftar gratis
            </Link>
          </p>
        </div>
        <OperatingHoursCard className="mt-6" />
      </div>
    </div>
  );
}
