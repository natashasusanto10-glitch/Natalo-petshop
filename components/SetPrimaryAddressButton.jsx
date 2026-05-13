"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function SetPrimaryAddressButton({ id, disabled = false }) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function setPrimary() {
    if (disabled || loading) return;
    setLoading(true);
    try {
      const response = await fetch(`/api/alamat/${id}/set-primary`, { method: "PATCH" });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error || "Gagal menjadikan alamat utama.");
      router.refresh();
    } finally {
      setLoading(false);
    }
  }

  return (
    <button
      type="button"
      onClick={setPrimary}
      disabled={disabled || loading}
      className="rounded-full border border-natalo-200 px-4 py-2 text-xs font-black text-natalo-700 transition hover:bg-natalo-50 disabled:cursor-not-allowed disabled:border-slate-200 disabled:text-slate-400"
    >
      {loading ? "Menyimpan..." : disabled ? "Alamat Utama" : "Jadikan Utama"}
    </button>
  );
}
