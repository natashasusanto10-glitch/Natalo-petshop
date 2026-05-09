"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";

interface Props {
  initialName: string;
  initialPhone: string | null;
  initialBirthDate: string | null;
  email: string | null;
}

type ProfileForm = {
  name: string;
  phone: string;
  birthDate: string;
};

type SaveState = "idle" | "saving" | "saved";

function buildInitialForm(initialName: string, initialPhone: string | null, initialBirthDate: string | null): ProfileForm {
  return {
    name: initialName,
    phone: initialPhone ?? "",
    birthDate: initialBirthDate ?? "",
  };
}

export function EditProfileForm({ initialName, initialPhone, initialBirthDate, email }: Props) {
  const router = useRouter();
  const savedTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [saveState, setSaveState] = useState<SaveState>("idle");
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState("");

  const [initialForm, setInitialForm] = useState<ProfileForm>(() =>
    buildInitialForm(initialName, initialPhone, initialBirthDate)
  );
  const [form, setForm] = useState<ProfileForm>(initialForm);

  const hasChanges = useMemo(
    () =>
      form.name !== initialForm.name ||
      form.phone !== initialForm.phone ||
      form.birthDate !== initialForm.birthDate,
    [form, initialForm]
  );

  const isSaving = saveState === "saving";
  const isSaved = saveState === "saved";
  const isSubmitDisabled = !hasChanges || isSaving || isSaved;

  const buttonText = isSaving
    ? "Menyimpan..."
    : isSaved
      ? "Tersimpan ✓"
      : hasChanges
        ? "Simpan Perubahan"
        : "Tidak Ada Perubahan";

  useEffect(() => {
    const nextInitialForm = buildInitialForm(initialName, initialPhone, initialBirthDate);
    setInitialForm(nextInitialForm);
    setForm(nextInitialForm);
  }, [initialName, initialPhone, initialBirthDate]);

  useEffect(() => {
    return () => {
      if (savedTimerRef.current) clearTimeout(savedTimerRef.current);
    };
  }, []);

  function update(field: string, value: string) {
    if (savedTimerRef.current) {
      clearTimeout(savedTimerRef.current);
      savedTimerRef.current = null;
    }
    setForm((prev) => ({ ...prev, [field]: value }));
    setSaveState("idle");
    setSuccess(false);
    setError("");
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!hasChanges || isSaving) return;

    if (savedTimerRef.current) {
      clearTimeout(savedTimerRef.current);
      savedTimerRef.current = null;
    }

    setError("");
    setSuccess(false);
    setSaveState("saving");

    const nextForm: ProfileForm = {
      name: form.name.trim(),
      phone: form.phone.trim(),
      birthDate: form.birthDate,
    };

    try {
      const res = await fetch("/api/member/profile", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: nextForm.name,
          phone: nextForm.phone || null,
          birthDate: nextForm.birthDate || null,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gagal menyimpan.");
      setForm(nextForm);
      setInitialForm(nextForm);
      setSuccess(true);
      setSaveState("saved");
      savedTimerRef.current = setTimeout(() => {
        setSaveState("idle");
        savedTimerRef.current = null;
      }, 1500);
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal menyimpan.");
      setSaveState("idle");
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
          Profil berhasil disimpan
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
          Nama <span className="text-blue-500">*</span>
        </label>
        <input
          type="text"
          required
          value={form.name}
          onChange={(e) => update("name", e.target.value)}
          placeholder="Nama lengkap"
          className="mt-2 block w-full rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm outline-none transition focus:border-blue-400 focus:ring-4 focus:ring-blue-100"
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
          className="mt-2 block w-full rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm outline-none transition focus:border-blue-400 focus:ring-4 focus:ring-blue-100"
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
          className="mt-2 block w-full rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm outline-none transition focus:border-blue-400 focus:ring-4 focus:ring-blue-100"
        />
        <p className="mt-1 text-xs text-gray-400">
          Isi tanggal lahir untuk mendapatkan voucher diskon di hari ulang tahunmu 🎂
        </p>
      </div>

      <button
        type="submit"
        disabled={isSubmitDisabled}
        className={`w-full rounded-full py-3 text-sm font-bold transition disabled:cursor-not-allowed ${
          hasChanges && !isSaved
            ? "bg-blue-500 text-white hover:bg-blue-600 disabled:opacity-60"
            : isSaved
              ? "bg-green-500 text-white"
              : "bg-gray-200 text-gray-500"
        }`}
      >
        {buttonText}
      </button>
    </form>
  );
}
