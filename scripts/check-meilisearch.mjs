/**
 * Diagnostic untuk Meilisearch.
 *
 * Cek:
 *   1. Env vars terisi
 *   2. Host reachable (HTTP)
 *   3. /health endpoint OK
 *   4. API key valid (akses /version)
 *   5. Index "products" ada dan punya dokumen
 *   6. Search sederhana berfungsi
 *
 * Cara pakai:
 *   node scripts/check-meilisearch.mjs                 # pakai env yang sudah di-export
 *   dotenv -e .env -- node scripts/check-meilisearch.mjs        # cek env prod (.env)
 *   dotenv -e .env.local -- node scripts/check-meilisearch.mjs  # cek env dev (.env.local)
 */

import { createRequire } from "module";

const require = createRequire(import.meta.url);
const { Meilisearch } = require("meilisearch");

const HOST = process.env.MEILISEARCH_HOST ?? "";
const KEY = process.env.MEILISEARCH_API_KEY ?? "";
const INDEX_NAME = process.env.MEILISEARCH_INDEX ?? "products";

const checks = [];

function record(name, ok, detail) {
  checks.push({ name, ok, detail });
  const icon = ok ? "[OK]  " : "[FAIL]";
  console.log(`${icon} ${name}${detail ? ` — ${detail}` : ""}`);
}

async function main() {
  console.log("=".repeat(60));
  console.log("  Meilisearch Diagnostic");
  console.log("=".repeat(60));
  console.log(`Host  : ${HOST || "(empty)"}`);
  console.log(`Key   : ${KEY ? `${KEY.slice(0, 6)}... (${KEY.length} chars)` : "(empty)"}`);
  console.log(`Index : ${INDEX_NAME}`);
  console.log("-".repeat(60));

  if (!HOST) {
    record("env MEILISEARCH_HOST", false, "kosong — set di .env atau Vercel env");
    bail();
  } else if (HOST.includes("localhost") || HOST.includes("127.0.0.1")) {
    record("env MEILISEARCH_HOST", true, `${HOST} (lokal — TIDAK bisa dipakai di Vercel)`);
  } else {
    record("env MEILISEARCH_HOST", true, HOST);
  }

  if (!KEY) {
    record("env MEILISEARCH_API_KEY", false, "kosong");
    bail();
  } else {
    record("env MEILISEARCH_API_KEY", true, `${KEY.length} chars`);
  }

  let health;
  try {
    const res = await fetch(`${HOST}/health`, { signal: AbortSignal.timeout(10_000) });
    health = await res.json().catch(() => ({}));
    record("GET /health", res.ok, health.status ?? `HTTP ${res.status}`);
    if (!res.ok) bail();
  } catch (e) {
    record("GET /health", false, `${e.name}: ${e.message}`);
    bail();
  }

  const meili = new Meilisearch({ host: HOST, apiKey: KEY });

  try {
    const version = await meili.getVersion();
    record("API key valid (GET /version)", true, `Meilisearch v${version.pkgVersion}`);
  } catch (e) {
    record("API key valid (GET /version)", false, e.message ?? String(e));
    console.log("\n   Hint: pastikan MEILISEARCH_API_KEY = master key (atau key dengan 'all' actions).");
    bail();
  }

  let indexExists = false;
  try {
    const idx = await meili.getIndex(INDEX_NAME);
    indexExists = true;
    record(`Index "${INDEX_NAME}" ada`, true, `primaryKey=${idx.primaryKey ?? "-"}`);
  } catch (e) {
    record(`Index "${INDEX_NAME}" ada`, false, e.code ?? e.message ?? String(e));
    console.log(`\n   Hint: jalankan 'npm run search:setup' untuk membuat index + settings.`);
  }

  if (indexExists) {
    try {
      const stats = await meili.index(INDEX_NAME).getStats();
      const ok = stats.numberOfDocuments > 0;
      record(
        "Index ada dokumen",
        ok,
        `${stats.numberOfDocuments} docs${stats.isIndexing ? " (indexing in progress)" : ""}`,
      );
      if (!ok) {
        console.log(`\n   Hint: jalankan 'npm run search:reindex' untuk populate dari DB.`);
      }
    } catch (e) {
      record("Index ada dokumen", false, e.message ?? String(e));
    }

    try {
      const result = await meili.index(INDEX_NAME).search("", { limit: 1 });
      record("Search dummy berhasil", true, `${result.estimatedTotalHits} total hits`);
    } catch (e) {
      record("Search dummy berhasil", false, e.message ?? String(e));
    }
  }

  console.log("-".repeat(60));
  const failed = checks.filter((c) => !c.ok);
  if (failed.length === 0) {
    console.log("Semua check lulus. Meilisearch siap dipakai.");
  } else {
    console.log(`${failed.length} check gagal:`);
    for (const c of failed) console.log(`  - ${c.name}: ${c.detail}`);
    process.exitCode = 1;
  }
}

function bail() {
  console.log("-".repeat(60));
  console.log("Diagnostic dihentikan karena prerequisite gagal.");
  process.exit(1);
}

main().catch((e) => {
  console.error("Unexpected error:", e);
  process.exit(1);
});
