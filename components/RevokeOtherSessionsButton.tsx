"use client";

import { useState } from "react";
import { natToast } from "@/components/Toast";

export default function RevokeOtherSessionsButton() {
  const [loading, setLoading] = useState(false);
  const [confirming, setConfirming] = useState(false);

  async function revoke() {
    setLoading(true);
    try {
      const res = await fetch("/api/account/sessions/revoke-others", { method: "POST" });
      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        natToast(data.error || "Gagal logout perangkat lain.", { kind: "err" });
        setLoading(false);
        setConfirming(false);
        return;
      }

      natToast("Berhasil logout dari semua perangkat lain.", { kind: "ok" });
      setLoading(false);
      setConfirming(false);
    } catch (error) {
      console.error(error);
      natToast("Tidak bisa terhubung ke server.", { kind: "err" });
      setLoading(false);
      setConfirming(false);
    }
  }

  if (!confirming) {
    return (
      <button
        type="button"
        onClick={() => setConfirming(true)}
        className="mt-4 flex w-full items-center justify-center gap-2 rounded-full bg-blue-500 py-3 text-sm font-bold text-white shadow-sm transition hover:bg-blue-600"
      >
        🚪 Logout dari semua perangkat lain
      </button>
    );
  }

  return (
    <div className="mt-4 rounded-2xl border border-red-200 bg-red-50 p-4">
      <p className="text-sm font-bold text-red-700">Yakin mau logout perangkat lain?</p>
      <p className="mt-1 text-xs text-red-600">
        Semua sesi di browser/HP lain akan dipaksa logout. Perangkat ini tetap login.
      </p>
      <div className="mt-3 flex gap-2">
        <button
          type="button"
          onClick={() => setConfirming(false)}
          disabled={loading}
          className="flex-1 rounded-full border border-red-300 bg-white py-2.5 text-sm font-bold text-red-700 hover:bg-red-100 disabled:opacity-50"
        >
          Batal
        </button>
        <button
          type="button"
          onClick={revoke}
          disabled={loading}
          className="flex-1 rounded-full bg-red-600 py-2.5 text-sm font-bold text-white hover:bg-red-700 disabled:opacity-50"
        >
          {loading ? "Memproses..." : "Ya, logout"}
        </button>
      </div>
    </div>
  );
}
