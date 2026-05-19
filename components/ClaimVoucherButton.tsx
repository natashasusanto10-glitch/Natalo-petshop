"use client";

import { useState } from "react";
import { formatRupiah } from "@/lib/format";

// Tier loyalty — sinkron dengan TIERS di
// app/api/member/claim-voucher/route.ts (server adalah source of truth).
// Earn rate: 1 poin per Rp20.000 belanja.
const TIERS = [
  { points: 20, discountAmount: 10000, minimumOrder: 150000 },
  { points: 50, discountAmount: 25000, minimumOrder: 300000 },
  { points: 75, discountAmount: 40000, minimumOrder: 500000 },
  { points: 100, discountAmount: 60000, minimumOrder: 700000 },
  { points: 200, discountAmount: 150000, minimumOrder: 1500000 },
] as const;

interface Props {
  totalPoints: number;
}

export function ClaimVoucherButton({ totalPoints }: Props) {
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<{ code: string; discountAmount: number; expiresAt: string } | null>(null);
  const [error, setError] = useState("");

  async function claim(points: number) {
    setLoading(true);
    setError("");
    setResult(null);

    const res = await fetch("/api/member/claim-voucher", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ points }),
    });

    const data = await res.json();
    setLoading(false);

    if (!res.ok) {
      setError(data.error || "Gagal menukar poin.");
      return;
    }

    setResult(data);
  }

  const affordableTiers = TIERS.filter((t) => t.points <= totalPoints);

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        disabled={totalPoints < TIERS[0].points}
        className="mt-3 w-full rounded-full bg-natalo-600 px-5 py-2.5 text-sm font-bold text-white hover:bg-natalo-700 disabled:cursor-not-allowed disabled:opacity-40"
      >
        🎁 Tukar Poin
      </button>
    );
  }

  return (
    <div className="mt-3 rounded-2xl border border-natalo-200 bg-natalo-50 p-4">
      <p className="text-sm font-bold text-gray-900">Tukar poin jadi voucher</p>

      {result ? (
        <div className="mt-3 rounded-xl border border-green-200 bg-green-50 p-4 text-center">
          <p className="text-xs text-green-600">Voucher berhasil dibuat!</p>
          <p className="mt-1 font-mono text-xl font-black text-green-700">{result.code}</p>
          <p className="mt-1 text-xs text-green-600">
            Diskon {formatRupiah(result.discountAmount)} • Berlaku 30 hari
          </p>
          <p className="mt-2 text-xs text-gray-500">Salin kode di atas dan gunakan saat checkout.</p>
          <button
            onClick={() => { setResult(null); setOpen(false); window.location.reload(); }}
            className="mt-3 rounded-full bg-green-600 px-4 py-2 text-xs font-bold text-white"
          >
            Selesai
          </button>
        </div>
      ) : (
        <>
          <div className="mt-3 space-y-2">
            {TIERS.map((tier) => {
              const canAfford = totalPoints >= tier.points;
              return (
                <button
                  key={tier.points}
                  onClick={() => claim(tier.points)}
                  disabled={!canAfford || loading}
                  className={`w-full rounded-xl border p-3 text-left text-sm transition ${
                    canAfford
                      ? "border-natalo-200 bg-white hover:border-natalo-400"
                      : "border-zinc-200 bg-zinc-50 opacity-50 cursor-not-allowed"
                  }`}
                >
                  <span className="font-bold text-gray-900">{tier.points} poin</span>
                  <span className="mx-2 text-gray-400">→</span>
                  <span className="font-bold text-natalo-700">
                    voucher diskon {formatRupiah(tier.discountAmount)}
                  </span>
                  <span className="ml-2 block text-[11px] font-semibold text-gray-400">
                    Min. belanja {formatRupiah(tier.minimumOrder)}
                  </span>
                  {!canAfford && (
                    <span className="ml-2 text-xs text-gray-400">
                      (butuh {tier.points - totalPoints} poin lagi)
                    </span>
                  )}
                </button>
              );
            })}
          </div>

          {error && <p className="mt-2 text-xs text-red-500">{error}</p>}
          {loading && <p className="mt-2 text-xs text-gray-500">Memproses...</p>}

          <button
            onClick={() => setOpen(false)}
            className="mt-3 text-xs font-semibold text-gray-400 hover:text-gray-600"
          >
            Batal
          </button>
        </>
      )}
    </div>
  );
}
