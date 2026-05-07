"use client";

import Link from "next/link";
import { Suspense, useState } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { OperatingHoursCard } from "@/components/OperatingHours";
import { PasswordInput } from "@/components/PasswordInput";

function ResetPasswordForm() {
  const sp = useSearchParams();
  const router = useRouter();
  const token = sp.get("token") ?? "";

  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState(false);

  if (!token) {
    return (
      <div className="rounded-3xl bg-white p-8 text-center shadow-sm">
        <span className="text-4xl">⚠️</span>
        <h2 className="mt-3 text-lg font-black text-gray-900">
          Link tidak valid
        </h2>
        <p className="mt-2 text-sm text-gray-500">
          Token reset tidak ditemukan. Silakan minta link reset baru.
        </p>
        <Link
          href="/member/forgot-password"
          className="mt-6 inline-flex w-full items-center justify-center rounded-full bg-natalo-600 px-4 py-3 text-sm font-bold text-white hover:bg-natalo-700"
        >
          Minta Link Baru
        </Link>
      </div>
    );
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");

    if (password.length < 8) {
      setError("Password minimal 8 karakter.");
      return;
    }
    if (password !== confirmPassword) {
      setError("Password dan konfirmasi tidak sama.");
      return;
    }

    setLoading(true);
    try {
      const res = await fetch("/api/auth/reset-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, password }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error || "Gagal reset password.");
      } else {
        setSuccess(true);
        // Auto-redirect ke login setelah 3 detik
        setTimeout(() => {
          router.push("/member/login");
        }, 3000);
      }
    } catch {
      setError("Tidak bisa terhubung ke server. Coba lagi.");
    } finally {
      setLoading(false);
    }
  }

  if (success) {
    return (
      <div className="rounded-3xl bg-white p-8 text-center shadow-sm">
        <span className="text-4xl">✅</span>
        <h2 className="mt-3 text-lg font-black text-gray-900">
          Password Berhasil Diubah!
        </h2>
        <p className="mt-2 text-sm text-gray-500">
          Kamu akan otomatis diarahkan ke halaman login...
        </p>
        <Link
          href="/member/login"
          className="mt-6 inline-flex w-full items-center justify-center rounded-full bg-natalo-600 px-4 py-3 text-sm font-bold text-white hover:bg-natalo-700"
        >
          Login Sekarang →
        </Link>
      </div>
    );
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="space-y-4 rounded-3xl bg-white p-8 shadow-sm"
    >
      <div>
        <label className="block text-sm font-medium text-gray-700">
          Password Baru
        </label>
        <PasswordInput
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          minLength={8}
          autoComplete="new-password"
          className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-2 focus:ring-natalo-100"
          placeholder="Masukkan password baru (min. 8 karakter)"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700">
          Konfirmasi Password
        </label>
        <PasswordInput
          value={confirmPassword}
          onChange={(e) => setConfirmPassword(e.target.value)}
          required
          minLength={8}
          autoComplete="new-password"
          className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-2 focus:ring-natalo-100"
          placeholder="Ulangi password yang sama"
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
        {loading ? "Menyimpan..." : "Simpan Password Baru"}
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
  );
}

export default function ResetPasswordPage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <span className="text-4xl" aria-hidden="true">
            🔑
          </span>
          <h1 className="mt-3 text-2xl font-black text-gray-900">
            Reset Password
          </h1>
          <p className="mt-1 text-sm text-gray-500">
            Buat password baru untuk akun kamu.
          </p>
        </div>

        <Suspense
          fallback={
            <div className="rounded-3xl bg-white p-8 shadow-sm">
              <p className="text-center text-sm text-gray-500">Memuat...</p>
            </div>
          }
        >
          <ResetPasswordForm />
        </Suspense>
        <OperatingHoursCard className="mt-6" />
      </div>
    </div>
  );
}
