#!/usr/bin/env node
/**
 * bump-sw-version.mjs — generate public/sw.js dgn cache version unik per build.
 *
 * Kenapa:
 *   Service Worker cache (PRECACHE list + runtime caches) di-keyed by
 *   `CACHE` constant di sw.js. Tiap deploy harus pakai key beda supaya
 *   activate handler nuke cache lama (lihat sw.js: caches.delete untuk
 *   keys !== CACHE). Tanpa ini, user yg buka site/PWA setelah deploy
 *   bisa stuck di HTML yg ke-cache saat ada bug deploy-window race.
 *
 * Source of version (priority):
 *   1. VERCEL_GIT_COMMIT_SHA — Vercel auto-set di build environment
 *   2. local `git rev-parse --short HEAD` — untuk build manual / staging
 *   3. fallback timestamp "dev-XXXXX" — untuk dev/CI tanpa git
 *
 * Output:
 *   public/sw.js (gitignored — regenerate setiap build/dev start)
 *
 * Template:
 *   public/sw.template.js (tracked di git) — placeholder `__SW_CACHE_VERSION__`
 *   di-replace dgn version final.
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const TEMPLATE = resolve(ROOT, "public/sw.template.js");
const OUTPUT = resolve(ROOT, "public/sw.js");
const PLACEHOLDER = "__SW_CACHE_VERSION__";

function resolveVersion() {
  // Vercel build: paling reliable, traceable ke commit
  const vercelSha = process.env.VERCEL_GIT_COMMIT_SHA;
  if (vercelSha) return `natalo-v-${vercelSha.slice(0, 7)}`;

  // Local git: fallback untuk build manual
  try {
    const sha = execSync("git rev-parse --short HEAD", {
      cwd: ROOT,
      stdio: ["ignore", "pipe", "ignore"],
    })
      .toString()
      .trim();
    if (sha) return `natalo-v-${sha}-local`;
  } catch {
    // not a git repo or no commits — fine, fallback below
  }

  // Last resort: timestamp. Tetap unik tiap run supaya cache busted.
  return `natalo-vdev-${Date.now().toString(36)}`;
}

function main() {
  if (!existsSync(TEMPLATE)) {
    console.error(`[sw-version] ❌ Template tidak ditemukan: ${TEMPLATE}`);
    process.exit(1);
  }

  const tpl = readFileSync(TEMPLATE, "utf8");
  if (!tpl.includes(PLACEHOLDER)) {
    console.error(
      `[sw-version] ❌ Placeholder "${PLACEHOLDER}" tidak ada di template — ` +
        `pastikan public/sw.template.js mengandung string ini sebagai cache key.`,
    );
    process.exit(1);
  }

  const version = resolveVersion();
  const out = tpl.replaceAll(PLACEHOLDER, version);
  writeFileSync(OUTPUT, out, "utf8");
  console.log(`[sw-version] ✓ Generated public/sw.js (CACHE="${version}")`);
}

main();
