"use client";

import Link from "next/link";
import { useState } from "react";
import { OperatingHoursCard } from "@/components/OperatingHours";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState("");

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);

    try {
      const res = await fetch("/api/auth/forgot-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error || "Gagal mengirim link reset.");
      } else {
        setSubmitted(true);
      }
    } catch {
      setError("Tidak bisa terhubung ke server. Coba lagi.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <span className="text-4xl" aria-hidden="true">
            🔐
          </span>
          <h1 className="mt-3 text-2xl font-black text-gray-900">
            Lupa Password?
          </h1>
          <p className="mt-1 text-sm text-gray-500">
            Masukkan email yang terdaftar. Kami akan kirim link reset ke kamu.
          </p>
        </div>

        {submitted ? (
          <div className="rounded-3xl bg-white p-8 shadow-sm">
            <div className="text-center">
              <span className="text-4xl" aria-hidden="true">
                📧
              </span>
              <h2 className="mt-3 text-lg font-black text-gray-900">
                Cek inbox kamu!
              </h2>
              <p className="mt-2 text-sm text-gray-600">
                Kalau email <strong>{email}</strong> terdaftar di sistem kami,
                kamu akan terima email berisi link reset password dalam beberapa menit.
              </p>
              <p className="mt-3 text-xs text-gray-500">
                💡 Tidak terima email? Cek folder <strong>Spam</strong> atau{" "}
                <strong>Promotions</strong>. Link berlaku 1 jam.
              </p>
            </div>
            <Link
              href="/member/login"
              className="mt-6 block rounded-full bg-natalo-600 px-4 py-3 text-center text-sm font-bold text-white transition hover:bg-natalo-700"
            >
              Kembali ke Login
            </Link>
          </div>
        ) : (
          <form
            onSubmit={handleSubmit}
            className="space-y-4 rounded-3xl bg-white p-8 shadow-sm"
          >
            <div>
              <label
                htmlFor="email"
                className="block text-sm font-medium text-gray-700"
              >
                Email
              </label>
              <input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
                className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-2 focus:ring-natalo-100"
                placeholder="Contoh: nama@email.com"
              />
            </div>

            {error && (
              <p className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-600">
                {error}
              </p>
            )}

            <button
              type="submit"
              disabled={loading}
              className="block w-full rounded-full bg-natalo-600 py-3 text-sm font-bold text-white transition hover:bg-natalo-700 disabled:opacity-50"
            >
              {loading ? "Mengirim..." : "Kirim Link Reset"}
            </button>

            <p className="text-center text-sm">
              <Link
                href="/member/login"
                className="font-semibold text-gray-600 hover:text-natalo-600 hover:underline"
              >
                ← Kembali ke Login
              </Link>
            </p>
          </form>
        )}
        <OperatingHoursCard className="mt-6" />
      </div>
    </div>
  );
}
