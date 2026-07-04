/**
 * Backfill: normalisasi semua logo Brand yang sudah ada di DB — trim
 * padding transparan + pad ulang ke kanvas seragam (lihat
 * lib/upload/normalize-logo.ts), lalu re-upload ke UploadThing dan update
 * Brand.logoUrl.
 *
 * Usage: npx tsx scripts/normalize-brand-logos.mjs
 *
 * Resume-safe: aman dijalankan berkali-kali — brand yang gagal di run
 * sebelumnya cukup dijalankan ulang, brand yang sudah sukses akan
 * dinormalisasi ulang lagi (idempoten secara visual, hanya boros 1 upload
 * ekstra kalau di-rerun tanpa alasan).
 * Pakai DATABASE_URL dan UPLOADTHING_TOKEN dari .env (= production).
 */
import { PrismaClient } from "@prisma/client";
import { UTApi } from "uploadthing/server";
import { normalizeBrandLogo } from "../lib/upload/normalize-logo.ts";

const prisma = new PrismaClient();
const utapi = new UTApi();

const BATCH = 4; // sharp CPU-bound — jangan terlalu paralel

async function processOne(brand) {
  const response = await fetch(brand.logoUrl);
  if (!response.ok) {
    throw new Error(`fetch failed: HTTP ${response.status}`);
  }
  const inputBuffer = Buffer.from(await response.arrayBuffer());
  const normalizedBuffer = await normalizeBrandLogo(inputBuffer);

  const filename = `brand-logo-${brand.slug}-${Date.now()}.png`;
  const file = new File([normalizedBuffer], filename, { type: "image/png" });
  const res = await utapi.uploadFiles(file);
  if (res.error || !res.data) {
    throw new Error(res.error?.message ?? "upload gagal");
  }

  await prisma.brand.update({
    where: { id: brand.id },
    data: { logoUrl: res.data.ufsUrl },
  });
}

async function main() {
  console.log("=== Normalisasi Brand.logoUrl (trim + pad seragam) ===\n");

  const brands = await prisma.brand.findMany({
    where: { logoUrl: { not: null } },
    select: { id: true, slug: true, name: true, logoUrl: true },
  });

  console.log(`Total brand dengan logo: ${brands.length}\n`);

  let done = 0;
  let failed = 0;
  const failures = [];
  const startTime = Date.now();

  for (let i = 0; i < brands.length; i += BATCH) {
    const batch = brands.slice(i, i + BATCH);
    await Promise.all(
      batch.map(async (brand) => {
        try {
          await processOne(brand);
          done++;
        } catch (e) {
          failed++;
          failures.push(`${brand.slug}: ${e.message}`);
        }
      }),
    );
    const elapsed = (Date.now() - startTime) / 1000;
    process.stdout.write(
      `\r[${done + failed}/${brands.length}] ok=${done} fail=${failed} elapsed=${Math.round(elapsed)}s`,
    );
  }

  console.log(`\n\n=== Selesai ===`);
  console.log(`Sukses: ${done}`);
  console.log(`Gagal: ${failed}`);
  if (failures.length > 0) {
    console.log(`\nDetail gagal:`);
    failures.forEach((f) => console.log(`  - ${f}`));
  }
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
