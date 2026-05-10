"use client";

import Link from "next/link";
import { useRef, useState } from "react";

type Summary = {
  categoriesUpserted: number;
  brandsUpserted: number;
  productsUpserted: number;
  variantsUpserted: number;
  skipped: number;
};

type BatchResponse = {
  ok: true;
  totalProducts: number;
  processedThisCall: number;
  processedSoFar: number;
  nextOffset: number;
  done: boolean;
  summary: Summary;
};

const DEFAULT_BATCH_SIZE = 80;

export default function ImportProductsPage() {
  const [running, setRunning] = useState(false);
  const [progress, setProgress] = useState<{
    processed: number;
    total: number;
  } | null>(null);
  const [totals, setTotals] = useState<Summary>({
    categoriesUpserted: 0,
    brandsUpserted: 0,
    productsUpserted: 0,
    variantsUpserted: 0,
    skipped: 0,
  });
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [logs, setLogs] = useState<string[]>([]);
  const [batchSize, setBatchSize] = useState(DEFAULT_BATCH_SIZE);
  const cancelRef = useRef(false);

  function appendLog(line: string) {
    setLogs((prev) => [...prev.slice(-100), line]);
  }

  async function runImport() {
    if (running) return;
    setRunning(true);
    setError(null);
    setDone(false);
    setLogs([]);
    setTotals({
      categoriesUpserted: 0,
      brandsUpserted: 0,
      productsUpserted: 0,
      variantsUpserted: 0,
      skipped: 0,
    });
    cancelRef.current = false;

    let offset = 0;
    let total = 0;
    appendLog(`Memulai import (batch size ${batchSize})...`);

    while (!cancelRef.current) {
      try {
        const res = await fetch("/api/admin/products/import", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ offset, batchSize }),
        });

        if (!res.ok) {
          const data = await res.json().catch(() => ({}));
          throw new Error(data.error ?? `HTTP ${res.status}`);
        }

        const data = (await res.json()) as BatchResponse;
        total = data.totalProducts;
        offset = data.nextOffset;

        setProgress({ processed: data.processedSoFar, total });
        setTotals((prev) => ({
          categoriesUpserted: Math.max(
            prev.categoriesUpserted,
            data.summary.categoriesUpserted,
          ),
          brandsUpserted: Math.max(
            prev.brandsUpserted,
            data.summary.brandsUpserted,
          ),
          productsUpserted: prev.productsUpserted + data.summary.productsUpserted,
          variantsUpserted: prev.variantsUpserted + data.summary.variantsUpserted,
          skipped: prev.skipped + data.summary.skipped,
        }));

        appendLog(
          `Batch [${data.processedSoFar - data.processedThisCall + 1}–${data.processedSoFar}] ` +
            `produk: ${data.summary.productsUpserted} ✔ · varian: ${data.summary.variantsUpserted} · skip: ${data.summary.skipped}`,
        );

        if (data.done) {
          setDone(true);
          appendLog(`Selesai: ${data.processedSoFar} dari ${total} produk diproses.`);
          break;
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : "Gagal menjalankan import.";
        setError(msg);
        appendLog(`ERROR: ${msg}`);
        break;
      }
    }

    setRunning(false);
  }

  function cancelImport() {
    cancelRef.current = true;
    appendLog("Pembatalan diminta — akan berhenti setelah batch berjalan selesai.");
  }

  const pct =
    progress && progress.total > 0
      ? Math.min(100, Math.round((progress.processed / progress.total) * 100))
      : 0;

  return (
    <div className="mx-auto max-w-3xl px-4 py-8">
      <div className="mb-6 flex items-center justify-between gap-3">
        <div>
          <Link
            href="/admin/products"
            className="text-xs font-bold text-zinc-500 hover:underline"
          >
            ← Kembali ke daftar produk
          </Link>
          <h1 className="mt-1 text-2xl font-black text-zinc-950">
            Import Produk dari Excel
          </h1>
          <p className="mt-1 text-sm text-zinc-500">
            Upsert seluruh produk, kategori, brand, dan varian dari{" "}
            <code className="rounded bg-zinc-100 px-1.5 py-0.5 text-xs">
              prisma/products_import.json
            </code>{" "}
            ke database production.
          </p>
        </div>
      </div>

      <div className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3">
        <p className="text-sm font-bold text-amber-900">⚠ Sebelum import</p>
        <ul className="mt-1.5 space-y-1 text-xs text-amber-800">
          <li>
            Pastikan{" "}
            <code className="rounded bg-amber-100 px-1 py-0.5">
              prisma/products_import.json
            </code>{" "}
            sudah ter-update di repo dan sudah di-deploy ke Vercel.
          </li>
          <li>
            Operasi ini upsert (tidak hapus produk lama). Produk yang slug-nya
            sama akan ter-update harga/stok/varian-nya.
          </li>
          <li>
            Untuk dataset besar (1000+ produk), proses bisa beberapa menit. Halaman
            ini me-loop call API per batch.
          </li>
        </ul>
      </div>

      <div className="mt-6 rounded-2xl border border-zinc-200 bg-white p-5">
        <div className="flex flex-wrap items-end gap-3">
          <label className="block text-sm">
            <span className="block font-bold text-zinc-700">Batch size</span>
            <input
              type="number"
              min={10}
              max={200}
              step={10}
              value={batchSize}
              onChange={(e) =>
                setBatchSize(
                  Math.min(200, Math.max(10, Number(e.target.value) || 80)),
                )
              }
              disabled={running}
              className="mt-1 block w-28 rounded-xl border border-zinc-300 px-3 py-2 text-sm outline-none focus:border-natalo-400 disabled:bg-zinc-50"
            />
          </label>
          <p className="text-xs text-zinc-500">
            Jumlah produk per call API. Kurangi kalau sering timeout.
          </p>
        </div>

        <div className="mt-5 flex items-center gap-3">
          <button
            type="button"
            onClick={runImport}
            disabled={running}
            className="rounded-xl bg-natalo-600 px-5 py-2.5 text-sm font-bold text-white transition hover:bg-natalo-700 disabled:cursor-not-allowed disabled:bg-zinc-300"
          >
            {running ? "Memproses..." : done ? "Jalankan Lagi" : "Mulai Import"}
          </button>
          {running && (
            <button
              type="button"
              onClick={cancelImport}
              className="rounded-xl border border-zinc-300 bg-white px-4 py-2.5 text-sm font-bold text-zinc-700 transition hover:bg-zinc-50"
            >
              Batalkan
            </button>
          )}
        </div>

        {/* Progress bar */}
        {progress && (
          <div className="mt-5">
            <div className="flex items-center justify-between text-xs font-bold text-zinc-700">
              <span>
                {progress.processed} / {progress.total} produk
              </span>
              <span>{pct}%</span>
            </div>
            <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-zinc-100">
              <div
                className={`h-full transition-all duration-300 ${
                  done ? "bg-emerald-500" : "bg-natalo-500"
                }`}
                style={{ width: `${pct}%` }}
              />
            </div>
          </div>
        )}

        {error && (
          <div className="mt-4 rounded-xl border border-red-200 bg-red-50 px-3 py-2.5 text-sm font-semibold text-red-700">
            {error}
          </div>
        )}

        {done && !error && (
          <div className="mt-4 rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2.5">
            <p className="text-sm font-bold text-emerald-800">
              ✅ Import selesai — halaman /products & /produk sudah di-revalidate.
            </p>
            <ul className="mt-2 space-y-0.5 text-xs text-emerald-900">
              <li>Kategori upserted: {totals.categoriesUpserted}</li>
              <li>Brand upserted: {totals.brandsUpserted}</li>
              <li>Produk upserted: {totals.productsUpserted}</li>
              <li>Varian upserted: {totals.variantsUpserted}</li>
              {totals.skipped > 0 && <li>Dilewati: {totals.skipped}</li>}
            </ul>
          </div>
        )}
      </div>

      {/* Log */}
      {logs.length > 0 && (
        <div className="mt-5 rounded-2xl border border-zinc-200 bg-zinc-950 p-4">
          <p className="text-xs font-bold uppercase tracking-wide text-zinc-400">
            Log
          </p>
          <pre className="mt-2 max-h-80 overflow-auto whitespace-pre-wrap break-words font-mono text-xs leading-5 text-zinc-100">
            {logs.join("\n")}
          </pre>
        </div>
      )}
    </div>
  );
}
