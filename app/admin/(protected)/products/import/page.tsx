"use client";

import Link from "next/link";
import { useRef, useState } from "react";
import { AdminPage, Button } from "@/components/admin/ui";

type Summary = {
  categoriesUpserted: number;
  brandsUpserted: number;
  productsUpserted: number;
  variantsUpserted: number;
  skipped: number;
  searchIndex?: { failed: number };
  staleDeactivated?: { count: number };
};

type BatchResponse = {
  ok: true;
  totalProducts: number;
  processedThisCall: number;
  processedSoFar: number;
  nextOffset: number;
  done: boolean;
  summary: Summary;
  issues?: { name: string; reason: string }[];
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
  const [searchFailures, setSearchFailures] = useState(0);
  const [archived, setArchived] = useState(0);
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [logs, setLogs] = useState<string[]>([]);
  const [batchSize, setBatchSize] = useState(DEFAULT_BATCH_SIZE);
  const [preview, setPreview] = useState<{ total: number; categories: number; brands: number; samples: string[] } | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [archiveMissing, setArchiveMissing] = useState(false);
  const cancelRef = useRef(false);

  function appendLog(line: string) {
    setLogs((prev) => [...prev.slice(-100), line]);
  }

  async function loadPreview() {
    setPreviewLoading(true); setError(null);
    try {
      const response = await fetch("/api/admin/products/import", { cache: "no-store" });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "Pratinjau gagal dimuat.");
      setPreview(result);
    } catch { setError("Pratinjau sumber gagal dimuat. Coba lagi."); }
    finally { setPreviewLoading(false); }
  }
  async function runImport() {
    if (running || !preview) return;
    setRunning(true); setProgress(null); setSearchFailures(0); setArchived(0);
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
          body: JSON.stringify({ offset, batchSize, archiveMissing }),
        });

        if (!res.ok) {
          const data = await res.json().catch(() => ({}));
          throw new Error(data.error ?? `HTTP ${res.status}`);
        }

        const data = (await res.json()) as BatchResponse;
        data.issues?.forEach(issue => appendLog(`${issue.name}: ${issue.reason}`));
        setSearchFailures(prev => prev + (data.summary.searchIndex?.failed ?? 0));
        setArchived(prev => prev + (data.summary.staleDeactivated?.count ?? 0));
        total = data.totalProducts;
        offset = data.nextOffset;

        setProgress({ processed: data.processedSoFar, total });
        setTotals((prev) => ({
          categoriesUpserted: Math.max(
            prev.categoriesUpserted,
            data.summary.categoriesUpserted
          ),
          brandsUpserted: Math.max(
            prev.brandsUpserted,
            data.summary.brandsUpserted
          ),
          productsUpserted:
            prev.productsUpserted + data.summary.productsUpserted,
          variantsUpserted:
            prev.variantsUpserted + data.summary.variantsUpserted,
          skipped: prev.skipped + data.summary.skipped,
        }));

        appendLog(
          `Batch [${data.processedSoFar - data.processedThisCall + 1}–${
            data.processedSoFar
          }] ` +
            `produk: ${data.summary.productsUpserted} ✔ · varian: ${data.summary.variantsUpserted} · skip: ${data.summary.skipped}`
        );

        if (data.done) {
          setDone(true);
          appendLog(
            `Selesai: ${data.processedSoFar} dari ${total} produk diproses.`
          );
          break;
        }
      } catch (err) {
        const msg =
          err instanceof Error ? err.message : "Gagal menjalankan import.";
        setError(msg);
        appendLog(`ERROR: ${msg}`);
        break;
      }
    }

    setRunning(false);
  }

  function cancelImport() {
    cancelRef.current = true;
    appendLog(
      "Pembatalan diminta — akan berhenti setelah batch berjalan selesai."
    );
  }

  const pct = progress?.total ? Math.round(progress.processed * 100 / progress.total) : 0;
  return (
    <AdminPage maxWidth="lg" className="admin-operational-page">
      <div className="mb-6 flex items-center justify-between gap-3">
        <div>
          <Link
            href="/admin/products"
            className="text-xs font-bold text-zinc-500 hover:underline"
          >
            ← Kembali ke daftar produk
          </Link>
          <h1 className="mt-1 text-2xl font-semibold text-zinc-950">
            Impor produk
          </h1>
          <p className="mt-1 text-sm text-zinc-500">
            Perbarui produk, kategori, brand, dan varian dari{" "}
            <code className="rounded bg-zinc-100 px-1.5 py-0.5 text-xs">
              prisma/products_import_new.json
            </code>{" "}
            ke katalog.
          </p>
        </div>
      </div>

      <div className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3">
        <p className="text-sm font-bold text-amber-900">⚠ Sebelum import</p>
        <ul className="mt-1.5 space-y-1 text-xs text-amber-800">
          <li>
            Pastikan{" "}
            <code className="rounded bg-amber-100 px-1 py-0.5">
              prisma/products_import_new.json
            </code>{" "}
            sudah ter-update di repo dan sudah di-deploy ke Vercel.
          </li>
          <li>
            Produk lama tetap disimpan. Produk yang slug-nya
            sama akan diperbarui harga, stok, dan variannya.
          </li>
          <li>
            Untuk dataset besar (1000+ produk), proses bisa beberapa menit.
            Produk diproses bertahap.
          </li>
        </ul>
      </div>

        <section className="my-5 rounded-2xl border border-slate-200 bg-white p-5 space-y-3">
        <h2 className="font-semibold">Periksa sumber impor</h2>
        <p className="text-sm text-slate-600">Impor memperbarui produk berdasarkan kode slug dari sumber JSON tersimpan. Produk yang tidak ada di sumber tetap disimpan.</p>
        <Button type="button" disabled={previewLoading || running} onClick={loadPreview}>{previewLoading ? "Memuat…" : "Pratinjau sumber"}</Button>
        {preview && <div className="text-sm"><p>{preview.total} produk · {preview.categories} kategori · {preview.brands} brand</p><ul className="mt-2 list-disc pl-5">{preview.samples.map((name, index) => <li key={index}>{name}</li>)}</ul></div>}
        <label className="flex items-start gap-2 text-sm"><input type="checkbox" checked={archiveMissing} disabled={running || !preview} onChange={event => setArchiveMissing(event.target.checked)} />Arsipkan juga produk yang tidak ada dalam sumber impor. Produk tersebut akan disembunyikan dari katalog.</label>
      </section>
      <div className="mt-6 rounded-2xl border border-zinc-200 bg-white p-5">
        <div className="flex flex-wrap items-end gap-3">
          <label className="block text-sm">
            <span className="block font-bold text-zinc-700">Batch size</span>
            <input
              type="text" inputMode="numeric" pattern="[0-9]+"
              min={10}
              max={200}
              step={10}
              value={batchSize}
              onChange={(e) =>
                setBatchSize(
                  Math.min(200, Math.max(10, Number(e.target.value) || 80))
                )
              }
              disabled={running || !preview}
              className="mt-1 block w-28 rounded-xl border border-zinc-300 px-3 py-2 text-sm outline-none focus:border-natalo-400 disabled:bg-zinc-50"
            />
          </label>
          <p className="text-xs text-zinc-500">
            Jumlah produk per tahap. Kurangi jika proses sering gagal.
          </p>
        </div>

        <div className="mt-5 flex items-center gap-3">
          <Button type="button" onClick={runImport} disabled={running || !preview}>
            {running ? "Memproses..." : done ? "Jalankan Lagi" : "Mulai Import"}
          </Button>
          {running && (
            <Button type="button" onClick={cancelImport} variant="secondary">
              Batalkan
            </Button>
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
                className={`h-full transition-[width] duration-300 ${
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
              Impor selesai — periksa ringkasan hasil di bawah.
            </p>
            <ul className="mt-2 space-y-0.5 text-xs text-emerald-900">
              <li>Kategori diperbarui: {totals.categoriesUpserted}</li>
              <li>Brand diperbarui: {totals.brandsUpserted}</li>
              <li>Produk diperbarui: {totals.productsUpserted}</li>
              <li>Varian diperbarui: {totals.variantsUpserted}</li>
              {archived > 0 && <li>Produk diarsipkan: {archived}</li>}
              {searchFailures > 0 && <li className="font-semibold text-amber-800">{searchFailures} produk belum tersinkron ke pencarian. Katalog tersimpan, indeks pencarian perlu diperiksa.</li>}
              {totals.skipped > 0 && <li>Dilewati: {totals.skipped}</li>}
            </ul>
          </div>
        )}
      </div>

      {logs.length > 0 && <details className="mt-4 rounded-xl border border-slate-200 p-4"><summary className="cursor-pointer text-sm font-semibold">Rincian proses</summary><ul className="mt-3 space-y-1 text-xs text-slate-600">{logs.map((line, index) => <li key={index}>{line}</li>)}</ul></details>}
      <p className="mt-6 text-sm text-slate-500">Penghapusan data tersedia terpisah di <Link className="underline" href="/admin/danger-zone">Pengaturan data</Link>.</p>
    </AdminPage>
  );
}
