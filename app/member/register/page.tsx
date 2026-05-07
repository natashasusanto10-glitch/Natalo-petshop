"use client";

import { useState } from "react";
import Link from "next/link";
import { OperatingHoursCard } from "@/components/OperatingHours";
import { PasswordInput } from "@/components/PasswordInput";

export default function MemberRegisterPage() {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");

    if (password !== confirmPassword) {
      setError("Password dan konfirmasi password tidak cocok.");
      return;
    }

    setLoading(true);

    const res = await fetch("/api/auth/member-register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name, email, phone, password, confirmPassword }),
    });

    const data = await res.json();
    setLoading(false);

    if (!res.ok) {
      setError(data.error || "Pendaftaran gagal");
      return;
    }

    window.location.replace("/member/login?registered=1");
  }

  return (
    <div className="flex min-h-screen items-start justify-center bg-gray-50 px-4 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <span className="text-4xl">🐾</span>
          <h1 className="mt-3 text-2xl font-black text-gray-900">Daftar Member</h1>
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
              className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-2 focus:ring-natalo-100"
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
              className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-2 focus:ring-natalo-100"
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
              className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-2 focus:ring-natalo-100"
              placeholder="Contoh: 08123456789"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Password</label>
            <PasswordInput
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
              className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-2 focus:ring-natalo-100"
              placeholder="Masukkan password Anda (min. 8 karakter)"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Konfirmasi password</label>
            <PasswordInput
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              required
              minLength={8}
              className="mt-1 block w-full rounded-xl border border-gray-200 px-4 py-3 text-sm outline-none transition focus:border-natalo-400 focus:ring-2 focus:ring-natalo-100"
              placeholder="Ulangi password yang sama"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700">Konfirmasi Password</label>
            <input
              type="password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              required
              minLength={8}
              className={`mt-1 block w-full rounded-xl border px-4 py-3 text-sm outline-none transition focus:ring-2 ${
                confirmPassword && confirmPassword !== password
                  ? "border-red-300 focus:border-red-400 focus:ring-red-100"
                  : "border-gray-200 focus:border-orange-400 focus:ring-orange-100"
              }`}
              placeholder="Ulangi password"
            />
            {confirmPassword && confirmPassword !== password && (
              <p className="mt-1 text-xs text-red-500">Password tidak cocok</p>
            )}
          </div>

          {error && (
            <p className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-600">{error}</p>
          )}

          <button
            type="submit"
            disabled={loading || (!!confirmPassword && confirmPassword !== password)}
            className="w-full rounded-full bg-orange-500 py-3 text-sm font-bold text-white transition hover:bg-orange-600 disabled:opacity-50"
          >
            {loading ? "Mendaftar..." : "Daftar Gratis"}
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
          <Link href="/member/login" className="font-semibold text-natalo-600 hover:underline">
            Masuk
          </Link>
        </p>
        <OperatingHoursCard className="mt-6" />
      </div>
    </div>
  );
}
