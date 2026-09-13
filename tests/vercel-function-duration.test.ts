/**
 * Menjaga aturan durasi fungsi di vercel.json benar-benar MENGENAI rute
 * yang dimaksud.
 *
 * Latar: `functions` di vercel.json ditulis dalam glob, dan di glob
 * `[id]` adalah character class ("satu huruf i atau d") — BUKAN nama
 * folder literal `[id]`. Jadi pola
 * `app/api/admin/products/[id]/generate-description/route.ts` tidak
 * pernah cocok dengan berkas rute dinamis Next.js, dan rutenya diam-diam
 * jatuh ke aturan umum 30 detik. Tak ada error, tak ada peringatan build
 * — hanya 504 saat dipakai. Pakai `*` untuk segmen dinamis.
 */
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test, { describe } from "node:test";

// Sama seperti test lain di repo ini: dijalankan dari akar repo
// (`npm test` -> `tsx --test tests/*.test.ts`).
const root = process.cwd();
const vercelConfig = JSON.parse(
  fs.readFileSync(path.join(root, "vercel.json"), "utf8"),
) as { functions: Record<string, { maxDuration?: number }> };

/**
 * Glob → RegExp, cukup untuk pola `*` dan `**` yang dipakai di sini.
 *
 * Sengaja TIDAK meniru character class: kurung siku di sini diperlakukan
 * sebagai huruf literal. Artinya pemeriksaan durasi di bawah tak bisa
 * menangkap pola `[id]` yang salah itu — yang menjaganya adalah test
 * "tak ada pola yang memakai kurung siku". Jangan hapus test itu dengan
 * anggapan test durasi sudah menutupinya.
 */
function globToRegExp(glob: string): RegExp {
  const source = glob
    .split("**")
    .map((chunk) =>
      chunk
        .split("*")
        .map((lit) => lit.replace(/[.+?^${}()|[\]\\]/g, "\\$&"))
        .join("[^/]*"),
    )
    .join(".*");
  return new RegExp(`^${source}$`);
}

/** maxDuration efektif: pola paling belakang yang cocok yang menang. */
function effectiveMaxDuration(file: string): number | undefined {
  let result: number | undefined;
  for (const [glob, cfg] of Object.entries(vercelConfig.functions)) {
    if (globToRegExp(glob).test(file)) result = cfg.maxDuration;
  }
  return result;
}

describe("vercel.json — durasi fungsi", () => {
  test("tak ada pola yang memakai kurung siku", () => {
    for (const glob of Object.keys(vercelConfig.functions)) {
      assert.ok(
        !/[[\]]/.test(glob),
        `Pola "${glob}" memakai kurung siku. Di glob itu character class, ` +
          "bukan folder dinamis Next.js — pakai * untuk segmen itu.",
      );
    }
  });

  test("kedua rute generate-description dapat 60 detik", () => {
    const routes = [
      "app/api/admin/products/generate-description/route.ts",
      "app/api/admin/products/[id]/generate-description/route.ts",
    ];
    for (const route of routes) {
      assert.ok(
        fs.existsSync(path.join(root, route)),
        `Rute ${route} tak ada — perbarui test ini kalau rutenya dipindah.`,
      );
      assert.equal(
        effectiveMaxDuration(route),
        60,
        `Rute ${route} tidak dapat 60 detik. Riset web makan 15-40 detik, ` +
          "jadi batas 30 detik memotongnya jadi 504.",
      );
    }
  });
});
