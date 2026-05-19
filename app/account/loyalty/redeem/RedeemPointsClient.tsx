"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createPortal } from "react-dom";
import { FiGift } from "react-icons/fi";
import { natToast } from "@/components/Toast";

// Tier loyalty — sinkron dengan TIERS di
// app/api/member/claim-voucher/route.ts (server adalah source of truth).
// Earn rate: 1 poin per Rp20.000 belanja.
const VOUCHER_TIERS = [
  { points: 20, discountAmount: 10000, minimumOrder: 150000 },
  { points: 50, discountAmount: 25000, minimumOrder: 300000 },
  { points: 75, discountAmount: 40000, minimumOrder: 500000 },
  { points: 100, discountAmount: 60000, minimumOrder: 700000 },
  { points: 200, discountAmount: 150000, minimumOrder: 1500000 },
] as const;

type VoucherTier = (typeof VOUCHER_TIERS)[number];

function formatVoucherAmount(amount: number) {
  return `Rp${new Intl.NumberFormat("id-ID").format(amount)}`;
}

export function RedeemPointsClient({ totalPoints }: { totalPoints: number }) {
  const router = useRouter();
  const [availablePoints, setAvailablePoints] = useState(totalPoints);
  const [selectedTier, setSelectedTier] = useState<VoucherTier | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const modalDescription = useMemo(() => {
    if (!selectedTier) return "";
    return (
      `Voucher ${formatVoucherAmount(selectedTier.discountAmount)} akan ditukar dengan ${
        selectedTier.points
      } poin. Berlaku dengan minimal belanja ${formatVoucherAmount(
        selectedTier.minimumOrder,
      )}.`
    );
  }, [selectedTier]);

  async function redeem() {
    if (!selectedTier) return;

    setLoading(true);
    setError("");

    try {
      const res = await fetch("/api/member/claim-voucher", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ points: selectedTier.points }),
      });
      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        setError(data.error || "Gagal menukar poin.");
        setLoading(false);
        return;
      }

      setAvailablePoints((current) => current - selectedTier.points);
      setSelectedTier(null);
      setLoading(false);
      router.refresh();
      natToast("Berhasil ditukar! Voucher sudah masuk ke Voucher Member.", {
        kind: "ok",
        action: {
          label: "Lihat Voucher Member",
          onClick: () => router.push("/member/vouchers"),
        },
      });
    } catch {
      setError("Tidak bisa terhubung ke server.");
      setLoading(false);
    }
  }

  const confirmationModal =
    selectedTier && typeof document !== "undefined"
      ? createPortal(
          <div
            className="fixed inset-0 z-[9999] flex items-center justify-center px-4"
            role="dialog"
            aria-modal="true"
            aria-labelledby="redeem-confirmation-title"
            aria-describedby="redeem-confirmation-description"
          >
            <button
              type="button"
              aria-label="Tutup konfirmasi tukar poin"
              onClick={() => {
                if (!loading) setSelectedTier(null);
              }}
              className="absolute inset-0 bg-black/35"
            />
            <div className="relative w-full max-w-sm rounded-[24px] bg-white p-5 text-center shadow-[0_24px_60px_rgba(15,23,42,0.24)]">
              <div className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-blue-50 text-natalo-600">
                <FiGift className="h-6 w-6" aria-hidden="true" />
              </div>
              <h2
                id="redeem-confirmation-title"
                className="mt-4 text-lg font-black leading-tight text-slate-950"
              >
                Tukar poin menjadi voucher?
              </h2>
              <div
                id="redeem-confirmation-description"
                className="mt-2 space-y-2 text-sm font-semibold leading-6 text-slate-500"
              >
                <p>{modalDescription}</p>
                <p>Poin akan dipotong setelah kamu konfirmasi.</p>
              </div>
              {error && <p className="mt-3 text-xs font-bold text-red-500">{error}</p>}
              <div className="mt-6 grid grid-cols-2 gap-3">
                <button
                  type="button"
                  onClick={() => setSelectedTier(null)}
                  disabled={loading}
                  className="h-11 rounded-2xl border border-slate-200 bg-white text-sm font-black text-slate-700 transition active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-60"
                >
                  Batal
                </button>
                <button
                  type="button"
                  onClick={redeem}
                  disabled={loading}
                  className="h-11 rounded-2xl bg-natalo-600 text-sm font-black text-white shadow-sm transition hover:bg-natalo-700 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {loading ? "Memproses..." : "Ya, Tukar"}
                </button>
              </div>
            </div>
          </div>,
          document.body,
        )
      : null;

  return (
    <>
      <section className="overflow-hidden rounded-2xl bg-gradient-to-br from-blue-500 to-blue-600 p-5 text-white shadow-sm md:p-6">
        <p className="text-xs uppercase tracking-wider text-blue-100">Saldo Poin Kamu</p>
        <p className="mt-2 text-4xl font-black md:text-5xl">
          {availablePoints.toLocaleString("id-ID")} poin
        </p>
        <p className="mt-1 text-xs text-blue-100">Tukar poin jadi voucher belanja</p>
        <p className="mt-0.5 text-xs text-blue-100">Voucher akan masuk ke Voucher Member</p>
      </section>

      <section className="mt-5">
        <h2 className="px-1 text-lg font-black text-slate-950">Pilih Voucher</h2>
        <div className="mt-3 space-y-3">
          {VOUCHER_TIERS.map((tier) => {
            const canRedeem = availablePoints >= tier.points;
            return (
              <article
                key={tier.points}
                className="flex items-center gap-3 rounded-[20px] border border-slate-100 bg-white p-4 shadow-[0_8px_24px_rgba(16,24,40,0.06)]"
              >
                <span className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl bg-[#EEF5FF] text-[#1677FF]">
                  <FiGift className="h-5 w-5" aria-hidden="true" />
                </span>
                <div className="min-w-0 flex-1">
                  <h3 className="text-sm font-black text-slate-950">
                    Voucher {formatVoucherAmount(tier.discountAmount)}
                  </h3>
                  <p className="mt-0.5 text-xs font-semibold text-slate-500">
                    Butuh {tier.points} poin
                  </p>
                  <p className="mt-0.5 text-[11px] font-semibold text-slate-400">
                    Min. belanja {formatVoucherAmount(tier.minimumOrder)}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setError("");
                    setSelectedTier(tier);
                  }}
                  disabled={!canRedeem || loading}
                  className={`shrink-0 rounded-full px-4 py-2 text-xs font-black transition active:scale-[0.98] ${
                    canRedeem
                      ? "bg-natalo-600 text-white hover:bg-natalo-700"
                      : "cursor-not-allowed bg-slate-100 text-slate-400"
                  }`}
                >
                  {canRedeem ? "Tukar" : "Poin belum cukup"}
                </button>
              </article>
            );
          })}
        </div>
      </section>

      <section className="mt-5 rounded-[20px] border border-slate-100 bg-white p-4 shadow-[0_8px_24px_rgba(16,24,40,0.06)]">
        <h2 className="text-sm font-black text-slate-950">Cara kerja penukaran</h2>
        <ul className="mt-3 space-y-2 text-sm font-semibold leading-5 text-slate-600">
          <li>- Poin akan dipotong setelah konfirmasi</li>
          <li>- Voucher masuk ke Voucher Member</li>
          <li>- Voucher dapat dipakai saat checkout</li>
        </ul>
      </section>

      {confirmationModal}
    </>
  );
}
