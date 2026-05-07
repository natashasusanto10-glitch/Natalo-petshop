"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

interface Props {
  initialName: string;
  initialPhone: string | null;
  initialBirthDate: string | null;
  email: string | null;
}

export function EditProfileForm({ initialName, initialPhone, initialBirthDate, email }: Props) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState("");

  const [form, setForm] = useState({
    name: initialName,
    phone: initialPhone ?? "",
    birthDate: initialBirthDate ?? "",
  });

  function update(field: string, value: string) {
    setForm((prev) => ({ ...prev, [field]: value }));
    setSuccess(false);
    setError("");
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setSuccess(false);
    setSubmitting(true);

    try {
      const res = await fetch("/api/member/profile", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: form.name.trim(),
          phone: form.phone.trim() || null,
          birthDate: form.birthDate || null,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gagal menyimpan.");
      setSuccess(true);
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mt-6 space-y-5">
      {error && (
        <div className="rounded-xl border border-red-100 bg-red-50 px-4 py-3 text-sm font-semibold text-red-600">
          {error}
        </div>
      )}
      {success && (
        <div className="rounded-xl border border-green-100 bg-green-50 px-4 py-3 text-sm font-semibold text-green-700">
          ✅ Profil berhasil disimpan.
        </div>
      )}

      {/* Email (read-only) */}
      <div>
        <label className="block text-xs font-semibold uppercase tracking-wide text-gray-400">
          Email
        </label>
        <p className="mt-1 rounded-xl border border-gray-100 bg-gray-50 px-4 py-3 text-sm text-gray-500">
          {email ?? "—"}
        </p>
        <p className="mt-1 text-xs text-gray-400">Email tidak bisa diubah.</p>
      </div>

      {/* Nama */}
      <div>
        <label className="block text-sm font-semibold text-gray-800">
          Nama <span className="text-orange-500">*</span>
        </label>
        <input
          type="text"
          required
          value={form.name}
          onChange={(e) => update("name", e.target.value)}
          placeholder="Nama lengkap"
          className="mt-2 block w-full rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm outline-none transition focus:border-orange-400 focus:ring-4 focus:ring-orange-100"
        />
      </div>

      {/* No. HP */}
      <div>
        <label className="block text-sm font-semibold text-gray-800">No. WhatsApp</label>
        <input
          type="tel"
          value={form.phone}
          onChange={(e) => update("phone", e.target.value)}
          placeholder="08xxxxxxxxxx atau +628xxxxxxxxxx"
          className="mt-2 block w-full rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm outline-none transition focus:border-orange-400 focus:ring-4 focus:ring-orange-100"
        />
      </div>

      {/* Tanggal Lahir */}
      <div>
        <label className="block text-sm font-semibold text-gray-800">Tanggal Lahir</label>
        <input
          type="date"
          value={form.birthDate}
          onChange={(e) => update("birthDate", e.target.value)}
          max={new Date().toISOString().split("T")[0]}
          className="mt-2 block w-full rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm outline-none transition focus:border-orange-400 focus:ring-4 focus:ring-orange-100"
        />
        <p className="mt-1 text-xs text-gray-400">
          Isi tanggal lahir untuk mendapatkan voucher diskon di hari ulang tahunmu 🎂
        </p>
      </div>

      <button
        type="submit"
        disabled={submitting}
        className="w-full rounded-full bg-orange-500 py-3 text-sm font-bold text-white transition hover:bg-orange-600 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {submitting ? "Menyimpan..." : "Simpan Perubahan"}
      </button>
    </form>
  );
}
