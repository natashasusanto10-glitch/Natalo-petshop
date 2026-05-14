"use client";

import { useState, useRef } from "react";

export function PaymentProofUpload({ orderNumber }: { orderNumber: string }) {
  const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");
  const [errorMsg, setErrorMsg] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const file = inputRef.current?.files?.[0];
    if (!file) return;

    setStatus("loading");
    const form = new FormData();
    form.append("file", file);

    const res = await fetch(`/api/orders/${orderNumber}/payment-proof`, {
      method: "POST",
      body: form,
    });

    if (res.ok) {
      setStatus("success");
    } else {
      const data = await res.json().catch(() => ({}));
      // API routes di codebase ini consistent return `{ error }` (lihat
      // app/api/orders/[orderNumber]/payment-proof/route.ts). Tetap support
      // `message` sebagai fallback untuk endpoint lain yg pakai konvensi
      // berbeda.
      setErrorMsg(data.error ?? data.message ?? "Gagal mengunggah. Coba lagi.");
      setStatus("error");
    }
  }

  function resetForm() {
    setStatus("idle");
    setErrorMsg("");
    if (inputRef.current) inputRef.current.value = "";
  }

  if (status === "success") {
    return (
      <div className="mt-4 space-y-3">
        <div className="rounded-2xl bg-green-50 p-4 text-center">
          <span className="text-2xl">✅</span>
          <p className="mt-1 font-semibold text-green-800">Bukti transfer berhasil dikirim!</p>
          <p className="mt-1 text-sm text-green-600">
            Tim kami akan mengkonfirmasi pembayaran kamu segera.
          </p>
        </div>
        {/* Recovery path — admin bisa minta upload ulang kalau ada masalah
            dgn proof yang dikirim (mis. screenshot blur, salah order). */}
        <button
          type="button"
          onClick={resetForm}
          className="w-full rounded-full border border-zinc-200 py-2.5 text-sm font-semibold text-zinc-700 transition-colors hover:bg-zinc-50"
        >
          Ganti bukti transfer
        </button>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="mt-4 space-y-3">
      <label
        htmlFor={`payment-proof-${orderNumber}`}
        className="block text-sm font-semibold text-zinc-700"
      >
        Upload Bukti Transfer
      </label>
      <input
        id={`payment-proof-${orderNumber}`}
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        required
        className="block w-full text-sm text-zinc-500 file:mr-4 file:rounded-full file:border-0 file:bg-blue-50 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-blue-600 hover:file:bg-blue-100"
      />
      {status === "error" && (
        <p className="text-sm text-red-500">{errorMsg}</p>
      )}
      <button
        type="submit"
        disabled={status === "loading"}
        className="w-full rounded-full bg-zinc-950 py-3 text-sm font-bold text-white disabled:opacity-50"
      >
        {status === "loading" ? "Mengunggah..." : "Kirim Bukti Transfer"}
      </button>
    </form>
  );
}
