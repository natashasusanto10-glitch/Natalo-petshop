"use client";

import { useState } from "react";
import { natToast } from "@/components/Toast";

const REASONS = [
  { value: "tidak_puas", label: "Tidak puas dengan layanan", hint: "Kami ingin tahu apa yang bisa diperbaiki" },
  { value: "tidak_butuh", label: "Tidak butuh aplikasi lagi", hint: "Hewan peliharaan tidak ada lagi, dll" },
  { value: "khawatir_privasi", label: "Khawatir privasi", hint: "Kami akan kirim ringkasan privasi sebelum hapus" },
  { value: "akun_lain", label: "Pakai akun lain", hint: "Mungkin kamu mau merge data?" },
  { value: "lainnya", label: "Alasan lainnya", hint: "Beri tahu kami via email setelah ini" },
] as const;

const CONFIRMATION_PHRASE = "HAPUS AKUN SAYA";

export default function DeleteAccountForm() {
  const [reason, setReason] = useState<string>(REASONS[0].value);
  const [confirmation, setConfirmation] = useState("");
  const [loading, setLoading] = useState(false);
  const canSubmit = confirmation === CONFIRMATION_PHRASE && !loading;

  async function handleDelete() {
    if (!canSubmit) return;
    setLoading(true);

    try {
      const res = await fetch("/api/account/delete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ reason, confirmation }),
      });

      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        natToast(data.error || "Gagal menghapus akun.", { kind: "err" });
        setLoading(false);
        return;
      }

      natToast("Akun kamu sudah dihapus. Sampai jumpa, semoga sehat selalu! 🐾", {
        kind: "ok",
      });
      window.setTimeout(() => {
        window.location.replace("/");
      }, 1200);
    } catch (error) {
      console.error(error);
      natToast("Tidak bisa terhubung ke server. Coba lagi.", { kind: "err" });
      setLoading(false);
    }
  }

  return (
    <div className="mt-4 space-y-3">
      <div>
        <p className="px-1 text-xs font-medium text-zinc-500">
          Pilih alasan kamu menghapus akun:
        </p>
        <div className="mt-2 space-y-2">
          {REASONS.map((r) => {
            const active = reason === r.value;
            return (
              <label
                key={r.value}
                className={`flex cursor-pointer items-start gap-3 rounded-2xl border bg-white p-4 transition ${
                  active ? "border-orange-400 ring-1 ring-orange-100" : "border-zinc-200 hover:border-orange-200"
                }`}
              >
                <input
                  type="radio"
                  name="delete-reason"
                  value={r.value}
                  checked={active}
                  onChange={() => setReason(r.value)}
                  className="sr-only"
                />
                <span
                  aria-hidden
                  className={`mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2 ${
                    active ? "border-orange-500" : "border-zinc-300"
                  }`}
                >
                  {active && <span className="h-2.5 w-2.5 rounded-full bg-orange-500" />}
                </span>
                <span className="flex-1">
                  <span className="block text-sm font-bold text-zinc-900">{r.label}</span>
                  <span className="mt-0.5 block text-xs text-zinc-500">{r.hint}</span>
                </span>
              </label>
            );
          })}
        </div>
      </div>

      <div className="rounded-2xl border border-red-200 bg-red-50 p-4">
        <p className="text-sm font-bold text-red-700">Konfirmasi penghapusan</p>
        <p className="mt-1 text-xs text-red-600">
          Ketik <b className="text-red-800">{CONFIRMATION_PHRASE}</b> untuk melanjutkan
        </p>
        <input
          type="text"
          value={confirmation}
          onChange={(e) => setConfirmation(e.target.value)}
          autoComplete="off"
          spellCheck={false}
          placeholder={CONFIRMATION_PHRASE}
          className="mt-3 block w-full rounded-xl border border-red-300 bg-white px-4 py-3 text-center text-sm font-bold uppercase tracking-wider outline-none focus:border-red-500 focus:ring-2 focus:ring-red-200"
        />
      </div>

      <button
        type="button"
        onClick={handleDelete}
        disabled={!canSubmit}
        className="w-full rounded-full bg-red-600 py-3 text-sm font-bold text-white shadow-sm transition hover:bg-red-700 disabled:cursor-not-allowed disabled:bg-red-300"
      >
        {loading ? "Menghapus..." : "🗑️ Hapus Akun Selamanya"}
      </button>
    </div>
  );
}
