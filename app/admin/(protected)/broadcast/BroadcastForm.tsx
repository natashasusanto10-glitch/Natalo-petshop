"use client";

import { useState } from "react";

type Segment = "all" | "members" | "active30d" | "test";

type Result = {
  ok: boolean;
  segment?: Segment;
  recipientCount?: number;
  sent?: number;
  failed?: number;
  elapsed_ms?: number;
  dryRun?: boolean;
  error?: string;
};

const SEGMENT_OPTIONS: Array<{ id: Segment; label: string; desc: string }> = [
  { id: "all", label: "Semua user", desc: "Semua yg subscribe push (PWA + iOS native)" },
  { id: "members", label: "Member (pernah belanja)", desc: "User dgn min. 1 order paymentStatus=PAID" },
  { id: "active30d", label: "Aktif 30 hari", desc: "User yg order dalam 30 hari terakhir" },
  { id: "test", label: "Test ke saya", desc: "Cuma admin yang trigger — preview test" },
];

export function BroadcastForm() {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [url, setUrl] = useState("");
  const [segment, setSegment] = useState<Segment>("test");
  const [recipientCount, setRecipientCount] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [result, setResult] = useState<Result | null>(null);
  const [error, setError] = useState("");

  const canSubmit = title.trim().length > 0 && body.trim().length > 0 && !loading;

  async function checkRecipientCount() {
    setError("");
    setLoading(true);
    try {
      const res = await fetch("/api/admin/push/broadcast", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title: title || "preview", body: body || "preview", url, segment, dryRun: true }),
      });
      const data: Result = await res.json();
      if (!res.ok) {
        setError(data.error ?? "Gagal cek recipient");
        return;
      }
      setRecipientCount(data.recipientCount ?? 0);
    } catch {
      setError("Gagal cek recipient (network)");
    } finally {
      setLoading(false);
    }
  }

  async function sendBroadcast() {
    setError("");
    setResult(null);
    setLoading(true);
    try {
      const res = await fetch("/api/admin/push/broadcast", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title, body, url, segment }),
      });
      const data: Result = await res.json();
      if (!res.ok) {
        setError(data.error ?? "Gagal kirim broadcast");
        return;
      }
      setResult(data);
      setConfirming(false);
    } catch {
      setError("Gagal kirim broadcast (network)");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="space-y-5">
      <div>
        <label className="block text-sm font-bold text-zinc-700">Title</label>
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          maxLength={60}
          placeholder="Promo Akhir Pekan 🔥"
          className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-400"
        />
        <p className="mt-1 text-xs text-zinc-400">{title.length}/60 karakter</p>
      </div>

      <div>
        <label className="block text-sm font-bold text-zinc-700">Pesan (body)</label>
        <textarea
          value={body}
          onChange={(e) => setBody(e.target.value)}
          maxLength={180}
          rows={3}
          placeholder="Diskon 20% semua pakan kucing s/d besok. Klik untuk lihat produk."
          className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-400"
        />
        <p className="mt-1 text-xs text-zinc-400">{body.length}/180 karakter</p>
      </div>

      <div>
        <label className="block text-sm font-bold text-zinc-700">URL tujuan saat di-klik (opsional)</label>
        <input
          type="text"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          placeholder="/products?kategori=kucing  (default: /)"
          className="mt-1 block w-full rounded-xl border border-zinc-300 px-4 py-3 text-sm outline-none focus:border-natalo-400"
        />
      </div>

      <div>
        <label className="block text-sm font-bold text-zinc-700">Target audience</label>
        <div className="mt-2 space-y-2">
          {SEGMENT_OPTIONS.map((opt) => (
            <label
              key={opt.id}
              className={`flex cursor-pointer items-start gap-3 rounded-xl border px-4 py-3 transition ${
                segment === opt.id ? "border-natalo-400 bg-natalo-50" : "border-zinc-200 bg-white"
              }`}
            >
              <input
                type="radio"
                name="segment"
                value={opt.id}
                checked={segment === opt.id}
                onChange={() => {
                  setSegment(opt.id);
                  setRecipientCount(null);
                }}
                className="mt-1 h-4 w-4 accent-natalo-600"
              />
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-bold text-zinc-950">{opt.label}</span>
                <span className="mt-0.5 block text-xs text-zinc-500">{opt.desc}</span>
              </span>
            </label>
          ))}
        </div>
      </div>

      <div className="rounded-xl border border-zinc-200 bg-zinc-50 px-4 py-3">
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="text-xs font-bold text-zinc-500 uppercase tracking-wide">Estimasi penerima</p>
            <p className="mt-1 text-2xl font-black text-zinc-900">
              {recipientCount !== null ? recipientCount.toLocaleString("id-ID") : "—"} user
            </p>
          </div>
          <button
            type="button"
            onClick={checkRecipientCount}
            disabled={loading}
            className="rounded-full border border-zinc-300 bg-white px-4 py-2 text-xs font-bold text-zinc-700 disabled:opacity-50"
          >
            Cek jumlah
          </button>
        </div>
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-semibold text-red-700">
          {error}
        </div>
      )}

      {result?.ok && (
        <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">
          <p className="font-bold">✅ Broadcast selesai</p>
          <ul className="mt-1.5 space-y-0.5 text-xs">
            <li>Segment: <strong>{result.segment}</strong></li>
            <li>Total recipient: <strong>{result.recipientCount}</strong></li>
            <li>Sukses: <strong>{result.sent}</strong></li>
            <li>Gagal: <strong>{result.failed}</strong></li>
            <li>Durasi: <strong>{result.elapsed_ms}ms</strong></li>
          </ul>
        </div>
      )}

      <div className="flex gap-3 pt-2">
        {!confirming ? (
          <button
            type="button"
            onClick={() => {
              if (!canSubmit) return;
              if (segment === "test") {
                // Test mode → langsung kirim ke admin saja, tidak perlu konfirmasi
                void sendBroadcast();
              } else {
                setConfirming(true);
              }
            }}
            disabled={!canSubmit}
            className="flex-1 rounded-full bg-natalo-600 px-6 py-3 text-sm font-bold text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:bg-zinc-300"
          >
            {segment === "test" ? "Test ke saya" : "Kirim broadcast"}
          </button>
        ) : (
          <>
            <button
              type="button"
              onClick={() => setConfirming(false)}
              disabled={loading}
              className="flex-1 rounded-full border border-zinc-300 bg-white px-6 py-3 text-sm font-bold text-zinc-700 disabled:opacity-50"
            >
              Batal
            </button>
            <button
              type="button"
              onClick={sendBroadcast}
              disabled={loading}
              className="flex-1 rounded-full bg-red-600 px-6 py-3 text-sm font-bold text-white transition active:bg-red-700 disabled:bg-zinc-300"
            >
              {loading ? "Mengirim..." : `Konfirmasi kirim${recipientCount !== null ? ` ke ${recipientCount} user` : ""}`}
            </button>
          </>
        )}
      </div>
    </div>
  );
}
