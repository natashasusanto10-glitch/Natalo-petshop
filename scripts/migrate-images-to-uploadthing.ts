/**
 * Migrate semua image local /uploads/* ke UploadThing CDN.
 * Update Product.imageUrl di Neon dengan URL UploadThing baru.
 *
 * Usage: npx tsx scripts/migrate-images-to-uploadthing.ts
 *
 * Resume-safe: skip produk yang imageUrl-nya sudah https://*.
 * Pakai DATABASE_URL dari .env (= Neon production).
 * Pakai UPLOADTHING_TOKEN dari .env.
 */
import { PrismaClient } from "@prisma/client";
import { UTApi } from "uploadthing/server";
import { readFile } from "fs/promises";
import { existsSync } from "fs";
import path from "path";

const prisma = new PrismaClient();
const utapi = new UTApi();

const BATCH = 8; // parallel uploads — naikkan kalau koneksi cepat

async function uploadOne(localPath: string, name: string) {
  const buffer = await readFile(localPath);
  const ext = path.extname(name).slice(1).toLowerCase();
  const mime = ext === "png" ? "image/png" : ext === "webp" ? "image/webp" : "image/jpeg";
  const file = new File([buffer], name, { type: mime });
  const res = await utapi.uploadFiles(file);
  if (res.error || !res.data) throw new Error(res.error?.message ?? "Upload fail");
  return res.data.ufsUrl;
}

async function main() {
  console.log("=== Migrate /uploads/* → UploadThing ===\n");

  const products = await prisma.product.findMany({
    where: {
      imageUrl: { startsWith: "/uploads/" },
    },
    select: { id: true, imageUrl: true },
  });

  console.log(`Total produk dengan local image: ${products.length}\n`);

  let done = 0;
  let failed = 0;
  const startTime = Date.now();

  // Helper untuk process satu produk
  async function processOne(p: { id: string; imageUrl: string | null }) {
    if (!p.imageUrl) return;
    const localPath = path.join("public", p.imageUrl);
    if (!existsSync(localPath)) {
      failed++;
      return;
    }
    try {
      const filename = path.basename(p.imageUrl);
      const newUrl = await uploadOne(localPath, filename);
      await prisma.product.update({
        where: { id: p.id },
        data: { imageUrl: newUrl },
      });
      done++;
    } catch (e) {
      failed++;
      if (failed <= 3) {
        console.error(`fail ${p.id}: ${(e as Error).message.slice(0, 80)}`);
      }
    }
  }

  // Batch parallel
  for (let i = 0; i < products.length; i += BATCH) {
    const batch = products.slice(i, i + BATCH);
    await Promise.all(batch.map(processOne));
    const elapsed = (Date.now() - startTime) / 1000;
    const rate = (done + failed) / elapsed;
    const eta = (products.length - (done + failed)) / rate;
    process.stdout.write(
      `\r[${done + failed}/${products.length}] ok=${done} fail=${failed} rate=${rate.toFixed(1)}/s eta=${Math.round(eta)}s`,
    );
  }

  console.log(`\n\n=== Selesai ===`);
  console.log(`Sukses: ${done}`);
  console.log(`Gagal: ${failed}`);
  console.log(`Waktu: ${Math.round((Date.now() - startTime) / 1000)}s`);
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
