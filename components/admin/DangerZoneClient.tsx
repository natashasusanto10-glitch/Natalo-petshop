"use client";

import { useState } from "react";
import { FiAlertTriangle, FiCheck, FiRefreshCw, FiTrash2 } from "react-icons/fi";

const CONFIRM_PHRASE = "RESET NATALO";

type ResetResult = {
  ok: boolean;
  durationMs?: number;
  deleted?: Record<string, number>;
  bunny?: {
    scanned: number;
    deleted: number;
    errors: number;
    bytesFreed: number;
  };
  note?: string;
  error?: string;
};

const DELETE_TARGETS = [
  "Semua customer user + data mereka",
  "Semua order + cart + voucher redemption",
  "Semua review + komentar",
  "Semua feed post + Bunny video library",
  "Semua produk + brand + kategori",
  "Semua point + favorite + pet + alamat",
  "Semua push subscription + notifikasi",
  "Semua chat thread + message",
];

const PRESERVED = [
  "Admin user (kamu tetap login)",
  "Schema database + migrations",
];

export function DangerZoneClient() {
  const [phrase, setPhrase] = useState("");
  const [confirmedRisk, setConfirmedRisk] = useState(false);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<ResetResult | null>(null);
  const [showFinal, setShowFinal] = useState(false);

  const phraseMatch = phrase.trim() === CONFIRM_PHRASE;
  const canSubmit = phraseMatch && confirmedRisk && !busy;

  async function executeReset() {
    if (!canSubmit) return;
    setBusy(true);
    setResult(null);
    try {
      const res = await fetch("/api/admin/reset-all", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ confirmPhrase: CONFIRM_PHRASE }),
      });
      const data = (await res.json()) as ResetResult;
      setResult({ ...data, ok: res.ok });
    } catch (err) {
      setResult({
        ok: false,
        error: err instanceof Error ? err.message : "Network error",
      });
    } finally {
      setBusy(false);
      setShowFinal(false);
    }
  }

  return (
    <div className="space-y-5">
      {/* What will be deleted */}
      <section className="rounded-2xl bg-white p-5 ring-1 ring-red-200">
        <h2 className="flex items-center gap-2 text-sm font-black text-red-900">
          <FiTrash2 className="h-4 w-4" /> Yang akan DI-HAPUS
        </h2>
        <ul className="mt-3 space-y-1 text-sm text-red-800">
          {DELETE_TARGETS.map((t) => (
            <li key={t} className="flex items-start gap-2">
              <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-red-500" />
              {t}
            </li>
          ))}
        </ul>
      </section>

      <section className="rounded-2xl bg-white p-5 ring-1 ring-emerald-200">
        <h2 className="flex items-center gap-2 text-sm font-black text-emerald-900">
          <FiCheck className="h-4 w-4" /> Yang DI-PRESERVE
        </h2>
        <ul className="mt-3 space-y-1 text-sm text-emerald-800">
          {PRESERVED.map((t) => (
            <li key={t} className="flex items-start gap-2">
              <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-500" />
              {t}
            </li>
          ))}
        </ul>
      </section>

      {/* Confirmation form */}
      <section className="rounded-2xl bg-white p-5 ring-1 ring-red-200">
        <h2 className="flex items-center gap-2 text-sm font-black text-red-900">
          <FiAlertTriangle className="h-4 w-4" /> Konfirmasi Reset
        </h2>

        <div className="mt-4 space-y-3">
          <label className="block">
            <span className="text-xs font-bold text-gray-700">
              Ketik <span className="font-mono text-red-700">{CONFIRM_PHRASE}</span> untuk konfirmasi
            </span>
            <input
              type="text"
              value={phrase}
              onChange={(e) => setPhrase(e.target.value)}
              placeholder={CONFIRM_PHRASE}
              disabled={busy}
              autoCapitalize="characters"
              autoCorrect="off"
              spellCheck={false}
              className={`mt-1 w-full rounded-xl border-2 px-3 py-2.5 text-sm font-mono transition focus:outline-none ${
                phraseMatch
                  ? "border-emerald-500 bg-emerald-50 text-emerald-900"
                  : "border-gray-200 bg-gray-50 text-gray-900 focus:border-red-500"
              }`}
            />
          </label>

          <label className="flex cursor-pointer items-start gap-2 text-sm text-gray-700">
            <input
              type="checkbox"
              checked={confirmedRisk}
              onChange={(e) => setConfirmedRisk(e.target.checked)}
              disabled={busy}
              className="mt-0.5 h-4 w-4 accent-red-600"
            />
            <span>
              Saya paham aksi ini <span className="font-black text-red-700">TIDAK BISA DI-UNDO</span> dan akan menghapus semua data customer, order, produk, feed, Bunny video, dan related data.
            </span>
          </label>

          {!showFinal ? (
            <button
              type="button"
              disabled={!canSubmit}
              onClick={() => setShowFinal(true)}
              className="mt-2 w-full rounded-xl bg-red-600 px-4 py-3 text-sm font-black text-white shadow-sm transition active:scale-[0.98] disabled:cursor-not-allowed disabled:bg-gray-300"
            >
              Lanjut ke Konfirmasi Final
            </button>
          ) : (
            <div className="mt-2 space-y-2 rounded-xl bg-red-100 p-4 ring-2 ring-red-400">
              <p className="text-sm font-black text-red-900">
                ⚠️ Konfirmasi terakhir. Aksi ini akan dijalankan IMMEDIATELY.
              </p>
              <p className="text-xs text-red-800">
                Setelah klik tombol di bawah, semua data akan terhapus dalam ~5-30 detik (tergantung jumlah). Bunny library juga akan di-purge.
              </p>
              <div className="flex gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setShowFinal(false)}
                  disabled={busy}
                  className="flex-1 rounded-xl bg-white px-4 py-2.5 text-sm font-black text-gray-700 ring-1 ring-gray-300 transition active:scale-[0.98]"
                >
                  Batal
                </button>
                <button
                  type="button"
                  onClick={executeReset}
                  disabled={busy}
                  className="flex-1 rounded-xl bg-red-700 px-4 py-2.5 text-sm font-black text-white transition active:scale-[0.98] disabled:bg-red-300"
                >
                  {busy ? (
                    <span className="inline-flex items-center gap-2">
                      <FiRefreshCw className="h-4 w-4 animate-spin" />
                      Menghapus...
                    </span>
                  ) : (
                    "EXECUTE RESET"
                  )}
                </button>
              </div>
            </div>
          )}
        </div>
      </section>

      {/* Result */}
      {result && (
        <section
          className={`rounded-2xl p-5 ring-1 ${
            result.ok
              ? "bg-emerald-50 ring-emerald-300"
              : "bg-red-100 ring-red-400"
          }`}
        >
          <h2 className="flex items-center gap-2 text-sm font-black">
            {result.ok ? (
              <>
                <FiCheck className="h-4 w-4 text-emerald-700" />
                <span className="text-emerald-900">Reset Berhasil</span>
              </>
            ) : (
              <>
                <FiAlertTriangle className="h-4 w-4 text-red-700" />
                <span className="text-red-900">Reset Gagal</span>
              </>
            )}
          </h2>

          {result.error && (
            <p className="mt-2 text-sm font-bold text-red-800">
              {result.error}
            </p>
          )}

          {result.ok && (
            <>
              <p className="mt-2 text-xs text-emerald-800">
                Selesai dalam {(result.durationMs ?? 0) / 1000}s.{" "}
                {result.note}
              </p>
              {result.bunny && (
                <div className="mt-3 rounded-xl bg-white p-3 text-xs ring-1 ring-emerald-200">
                  <p className="font-black text-emerald-900">Bunny Library:</p>
                  <p className="mt-1 text-emerald-800">
                    {result.bunny.deleted} video deleted (
                    {Math.round((result.bunny.bytesFreed ?? 0) / 1024 / 1024)}{" "}
                    MB freed)
                    {result.bunny.errors > 0
                      ? ` — ${result.bunny.errors} error`
                      : ""}
                  </p>
                </div>
              )}
              {result.deleted && (
                <div className="mt-3 rounded-xl bg-white p-3 text-xs ring-1 ring-emerald-200">
                  <p className="mb-1 font-black text-emerald-900">
                    Database rows deleted:
                  </p>
                  <div className="grid grid-cols-2 gap-x-3 gap-y-1 font-mono">
                    {Object.entries(result.deleted)
                      .filter(([, v]) => v > 0)
                      .sort((a, b) => b[1] - a[1])
                      .map(([k, v]) => (
                        <div key={k} className="flex justify-between text-emerald-800">
                          <span>{k}</span>
                          <span className="font-bold">{v}</span>
                        </div>
                      ))}
                  </div>
                </div>
              )}
            </>
          )}
        </section>
      )}
    </div>
  );
}
