"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";

export default function MemberLoginPage() {
  const router = useRouter();
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);

    const res = await fetch("/api/auth/member-login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ identifier, password }),
    });

    const data = await res.json();
    setLoading(false);

    if (!res.ok) {
      setError(data.error || "Login gagal");
      return;
    }

    router.push("/member");
    router.refresh();
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <span className="text-4xl">🐾</span>
          <h1 className="mt-3 text-2xl font-black text-gray-900">Masuk Member</h1>
          <p className="mt-1 text-sm text-gray-500">Gunakan email atau nomor HP yang terdaftar.</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4 rounded-3xl bg-white p-8 shadow-sm">
          <div>
            <label className="block text-sm font-medium text-gray-700">Email / No. HP</label>
            <input
              type="text"
              value={identifier}
              onChange={(e) => setIdentifier(e.target.value)}
              required
              className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-orange-400 focus:ring-2 focus:ring-orange-100"
              placeholder="email@kamu.com atau 08123..."
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Password</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-orange-400 focus:ring-2 focus:ring-orange-100"
              placeholder="••••••••"
            />
          </div>

          {error && (
            <p className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-600">{error}</p>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-full bg-orange-500 py-3 text-sm font-bold text-white transition hover:bg-orange-600 disabled:opacity-50"
          >
            {loading ? "Masuk..." : "Masuk"}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-gray-500">
          Belum punya akun?{" "}
          <Link href="/member/register" className="font-semibold text-orange-500 hover:underline">
            Daftar gratis
          </Link>
        </p>
        <p className="mt-3 text-center text-sm text-gray-400">
          Lupa password?{" "}
          <a
            href={`https://wa.me/${(process.env.NEXT_PUBLIC_WHATSAPP_NUMBER ?? "").replace("+", "")}?text=${encodeURIComponent("Halo, saya lupa password akun member saya. Mohon bantuan reset password.")}`}
            target="_blank"
            rel="noreferrer"
            className="font-semibold text-gray-500 hover:text-orange-500 hover:underline"
          >
            Hubungi kami via WhatsApp
          </a>
        </p>
      </div>
    </div>
  );
}
