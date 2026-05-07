/**
 * Setelah foto di-download (Downloads/images/) dan di-upload ke folder
 * public/uploads/products/ di project ini (atau ke server kamu),
 * jalankan script ini untuk mengganti URL gambar di database
 * dari Shopee CDN ke path lokal.
 *
 * Cara pakai:
 *   1. Copy seluruh isi Downloads/images/ ke public/uploads/products/
 *      (atau upload ke server, lalu set BASE_URL ke domain server)
 *   2. node scripts/update-image-urls.mjs
 *
 * Opsi:
 *   --dry-run    simulasi tanpa nulis ke DB
 *   --base=URL   ganti base URL (default: /uploads/products)
 */

import { createRequire } from "module";
import { readFileSync, existsSync } from "fs";
import { fileURLToPath } from "url";
import path from "path";

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const { PrismaClient } = require("@prisma/client");
const prisma = new PrismaClient();

const PRODUCTS_JSON = path.resolve(__dirname, "../../../Downloads/products.json");
const IMAGES_FOLDER = path.resolve(__dirname, "../public/uploads/products");
const DRY_RUN = process.argv.includes("--dry-run");
const baseArg = process.argv.find(a => a.startsWith("--base="));
const BASE_URL = baseArg ? baseArg.split("=")[1] : "/uploads/products";

async function main() {
  console.log("=".repeat(60));
  console.log("  Update URL Gambar: Shopee CDN → Lokal");
  console.log("=".repeat(60));
  if (DRY_RUN) console.log("🔍 DRY RUN — tidak ada yang ditulis ke database");
  console.log(`Base URL : ${BASE_URL}`);
  console.log(`Folder   : ${IMAGES_FOLDER}\n`);

  const products = JSON.parse(readFileSync(PRODUCTS_JSON, "utf8"));

  // Map: source_url → filename
  const urlToFilename = {};
  for (const p of products) {
    for (const img of (p.images || [])) {
      urlToFilename[img.source_url] = img.filename;
    }
  }

  // Ambil semua produk dari database yang punya imageUrl Shopee
  const dbProducts = await prisma.product.findMany({
    where: { imageUrl: { contains: "shopee" } },
    select: { id: true, slug: true, imageUrl: true },
  });

  console.log(`📦 ${dbProducts.length} produk masih pakai URL Shopee\n`);

  let ok = 0, missing = 0, skip = 0;
  const missingFiles = [];

  for (const p of dbProducts) {
    const filename = urlToFilename[p.imageUrl];
    if (!filename) {
      skip++;
      continue;
    }

    // Cek apakah file fisik sudah ada (skip pengecekan kalau BASE_URL adalah domain remote)
    if (BASE_URL.startsWith("/") && !existsSync(path.join(IMAGES_FOLDER, filename))) {
      missing++;
      missingFiles.push(filename);
      continue;
    }

    const newUrl = `${BASE_URL}/${filename}`;
    if (!DRY_RUN) {
      await prisma.product.update({
        where: { id: p.id },
        data: { imageUrl: newUrl },
      });
    }
    ok++;
  }

  console.log("=".repeat(60));
  console.log(`✅ Berhasil di-update : ${ok}`);
  console.log(`⏭️  Di-skip (tidak match): ${skip}`);
  console.log(`❌ File belum ada     : ${missing}`);
  if (missing > 0 && missingFiles.length > 0) {
    console.log(`\nContoh file yang belum ada di ${IMAGES_FOLDER}:`);
    missingFiles.slice(0, 10).forEach(f => console.log("   " + f));
    if (missingFiles.length > 10) console.log(`   ... dan ${missingFiles.length - 10} lainnya`);
    console.log("\nTip: pastikan Downloads/images/ sudah di-copy ke public/uploads/products/");
  }
  console.log("=".repeat(60));
}

main()
  .catch(e => { console.error(e); process.exit(1); })
  .finally(() => prisma.$disconnect());
